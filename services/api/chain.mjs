import {createPublicClient, createWalletClient, http, hashTypedData, keccak256, encodeFunctionData, parseEventLogs} from 'viem';
import {CircleAttestor} from './circle-attestor.mjs';
import {settlementNetwork} from './networks.mjs';
import {privateKeyToAccount} from 'viem/accounts';
import {domain, contractGrant, contractAction, grantTypes, actionDigest, proofTypes} from './protocol.mjs';
import {SerialQueue, ProductError, requireValue} from './errors.mjs';
import {loadArtifact} from './config.mjs';

export const tokenABI = [
  {type:'function',name:'balanceOf',stateMutability:'view',inputs:[{name:'account',type:'address'}],outputs:[{type:'uint256'}]},
  {type:'function',name:'decimals',stateMutability:'view',inputs:[],outputs:[{type:'uint8'}]},
];
/** Persist signed transaction bytes before broadcast; retries always resend identical bytes. */
export class TransactionLane {
  #public; #wallet; #account; #journal; #queue = new SerialQueue(); #prefix;
  constructor({publicClient,rpcURL,key,journal,chainId=11155111}) {
    this.#public=publicClient;this.#account=privateKeyToAccount(key);this.#journal=journal;
    this.#wallet=createWalletClient({account:this.#account,chain:settlementNetwork(chainId).chain,transport:http(rpcURL,{retryCount:0,timeout:20_000})});
    this.#prefix=`tx:${chainId===11155111?'':`${chainId}:`}${this.#account.address.toLowerCase()}:`;
  }
  get address(){return this.#account.address;}
  async #settle(id, entry) {
    if(entry.state==='confirmed') return entry.value;
    if(entry.state==='reverted') throw new ProductError('transaction_reverted','取引は取り消されました。新しい委任または条件を確認してください。',409);
    const value=entry.value;
    // Already-known errors and lost broadcast responses are indistinguishable from a
    // successfully broadcast transaction here. Only a real receipt advances the journal.
    await this.#public.sendRawTransaction({serializedTransaction:value.raw}).catch(()=>{});
    const receipt=await this.#public.waitForTransactionReceipt({hash:value.hash,confirmations:2,timeout:90_000,pollingInterval:2_000});
    requireValue(receipt.transactionHash.toLowerCase()===value.hash.toLowerCase(),'transaction_replaced','別の取引に置き換わりました。',409);
    const block=await this.#public.getBlock({blockNumber:receipt.blockNumber});
    requireValue(block.hash===receipt.blockHash,'reorg','確定ブロックを再確認してください。',409);
    const updated={...value,blockNumber:String(receipt.blockNumber)};
    this.#journal.put(id,receipt.status==='success'?'confirmed':'reverted',updated);
    if(receipt.status!=='success') throw new ProductError('transaction_reverted','取引がrevertしました。支払い成功とは扱っていません。',409);
    return updated;
  }
  async send(operation, {to,data,value=0n}) {
    return this.#queue.run(async()=>{
      const id=this.#prefix+operation;
      const existing=this.#journal.get(id);
      if(existing){
        requireValue(existing.value.to?.toLowerCase()===to?.toLowerCase() && existing.value.data===data && existing.value.value===String(value),
          'transaction_conflict','同じ操作識別子の内容が変わっています。',409);
        return this.#settle(id,existing);
      }
      // Do not allocate a new nonce while an older transaction has an unknown outcome.
      for(const item of this.#journal.pending(this.#prefix)) await this.#settle(item.id,item);
      const request=await this.#wallet.prepareTransactionRequest({account:this.#account,to,data,value});
      const raw=await this.#wallet.signTransaction(request);
      const prepared={raw,hash:keccak256(raw),to:to??null,data,value:String(value)};
      this.#journal.put(id,'prepared',prepared);
      return this.#settle(id,{state:'prepared',value:prepared});
    });
  }
}
export class Chain {
  constructor(config,journal) {
    this.config={...config,chainId:config.chainId??11155111};
    this.journal=journal;
    const chainId=this.config.chainId;
    this.public=createPublicClient({chain:settlementNetwork(chainId).chain,transport:http(config.rpcURL,{retryCount:1,timeout:20_000})});
    this.abi=loadArtifact('MateVault').abi;
    this.lane=config.relayerKey ? new TransactionLane({publicClient:this.public,rpcURL:config.rpcURL,key:config.relayerKey,journal,chainId}) : null;
    this.attestor=config.attestorMode==='circle' ? new CircleAttestor({walletAddress:config.attestorAddress,vault:config.vault,chainId,executable:config.circleCLI,cliHome:config.circleHome})
      : config.attestorKey ? privateKeyToAccount(config.attestorKey) : null;
  }
  async prepare(){
    const binding={chainId:this.config.chainId,vault:this.config.vault.toLowerCase(),token:this.config.token.toLowerCase()};
    const stored=this.journal.get('settlement-binding');
    requireValue(!stored || JSON.stringify(stored.value)===JSON.stringify(binding),'deployment_changed',
      'This journal belongs to another deployment. Recover it with its original configuration; use a separate data directory for a new deployment.',503);

    requireValue(await this.public.getChainId()===this.config.chainId,'wrong_chain','The RPC network does not match the approved settlement chain.',503);
    const [code,token,attestor]=await Promise.all([
      this.public.getCode({address:this.config.vault}),this.read('token'),this.read('attestor'),
    ]);
    requireValue(code && code!=='0x' && token.toLowerCase()===this.config.token.toLowerCase()
      && attestor.toLowerCase()===(this.attestor?.address||this.config.attestorAddress)?.toLowerCase(),'vault_configuration','コントラクトと設定が一致しません。',503);
    const decimals=await this.public.readContract({address:token,abi:tokenABI,functionName:'decimals'});
    requireValue(decimals===6,'token_decimals','6桁のテストUSDCのみ利用できます。',503);
    if(this.attestor instanceof CircleAttestor)await this.attestor.prepare();
    if(!stored)this.journal.put('settlement-binding','confirmed',binding);
  }
  read(functionName,args=[]) {return this.public.readContract({address:this.config.vault,abi:this.abi,functionName,args});}
  async state(id){
    const [owner,agent,policyHash,validUntil,spent,revoked]=await this.read('delegations',[id]);
    requireValue(owner!=='0x0000000000000000000000000000000000000000','mandate_not_found','委任が見つかりません。',404);
    return {owner,agent,policyHash,validUntil:Number(validUntil),spent:String(spent),revoked};
  }
  async account(owner){
    const [nonce,balance,tokenBalance,gasBalance]=await Promise.all([
      this.read('ownerNonces',[owner]),this.read('balances',[owner]),
      this.public.readContract({address:this.config.token,abi:tokenABI,functionName:'balanceOf',args:[owner]}),
      this.public.getBalance({address:owner}),
    ]);
    return {nonce:String(nonce),balance:String(balance),tokenBalance:String(tokenBalance),gasBalance:String(gasBalance)};
  }
  grantID(grant){return hashTypedData({domain:domain(this.config.chainId,this.config.vault),types:grantTypes,primaryType:'Grant',message:contractGrant(grant)});}
  async verifyOwner(grant,signature){return this.public.verifyTypedData({address:grant.owner,domain:domain(this.config.chainId,this.config.vault),types:grantTypes,primaryType:'Grant',message:contractGrant(grant),signature});}
  async register(grant,signature){
    const mandateId=this.grantID(grant);
    // An old registration remains recoverable even after its validity period ends.
    const tx=await this.lane.send(`grant:${mandateId}`,{to:this.config.vault,
      data:encodeFunctionData({abi:this.abi,functionName:'register',args:[contractGrant(grant),signature]})});
    return {mandateId,transactionHash:tx.hash,blockNumber:tx.blockNumber};
  }
  async verifyAgent(action,signature,state){
    return this.public.verifyTypedData({address:state.agent,domain:domain(this.config.chainId,this.config.vault),
      types:{Execution:[{name:'actionHash',type:'bytes32'}]},primaryType:'Execution',
      message:{actionHash:actionDigest(this.config.chainId,this.config.vault,action)},signature});
  }
  async pay(action,signature,proofHash){
    const actionHash=actionDigest(this.config.chainId,this.config.vault,action);
    const approvalDocument={domain:domain(this.config.chainId,this.config.vault),types:proofTypes,
      primaryType:'ProofApproval',message:{actionHash,proofHash}};
    const approvalID=`approval:${actionHash}:${proofHash}`;
    let proofApproval=this.journal.get(approvalID)?.value.signature;
    if(!proofApproval) {
      proofApproval=await this.attestor.signTypedData(approvalDocument);
      requireValue(await this.public.verifyTypedData({address:this.attestor.address,...approvalDocument,signature:proofApproval}),
        'attestor_signature','The proof attestor returned an invalid signature.',503);
      // Preserve exact calldata across retries even if the external signer uses nondeterministic signatures.
      this.journal.put(approvalID,'confirmed',{signature:proofApproval});
    }
    const tx=await this.lane.send(`execute:${actionHash}`,{to:this.config.vault,
      data:encodeFunctionData({abi:this.abi,functionName:'execute',args:[contractAction(action),proofHash,signature,proofApproval]})});
    const event=await this.executionEvent(tx.hash,action,proofHash);
    return {transactionHash:tx.hash,blockNumber:tx.blockNumber,actionHash,proofHash,spentAfter:String(event.spentAfter)};
  }
  async executionEvent(hash,action,proofHash){
    const receipt=await this.public.waitForTransactionReceipt({hash,confirmations:2,timeout:90_000});
    requireValue(receipt.status==='success','payment_unconfirmed','支払いが確定していません。',409);
    const canonical=await this.public.getBlock({blockNumber:receipt.blockNumber});
    requireValue(canonical.hash===receipt.blockHash,'payment_reorg','支払いブロックを再確認してください。',409);
    const logs=parseEventLogs({abi:this.abi,eventName:'Executed',logs:receipt.logs.filter(log=>log.address.toLowerCase()===this.config.vault.toLowerCase()),strict:true});
    const hashExpected=actionDigest(this.config.chainId,this.config.vault,action);
    const event=logs.find(log=>log.args.actionHash.toLowerCase()===hashExpected.toLowerCase())?.args;
    requireValue(event && event.mandateId.toLowerCase()===action.mandateId.toLowerCase()
      && event.recipient.toLowerCase()===action.recipient.toLowerCase() && event.amount===BigInt(action.amount)
      && event.service===action.service && event.nonce.toLowerCase()===action.nonce.toLowerCase()
      && event.proofHash.toLowerCase()===proofHash.toLowerCase(),'payment_mismatch','支払記録と依頼が一致しません。',409);
    return event;
  }
}
