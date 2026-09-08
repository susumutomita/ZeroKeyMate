import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {ProductError,requireValue} from './errors.mjs';
import {address,hash32,signatureSchema} from './protocol.mjs';

const run=promisify(execFile);
/** Circle Agent Stack holds only the proof attestation key, never the private policy. */
export class CircleAttestor {
  constructor({walletAddress,vault,chainId,executable='circle',cliHome},invoke=run) {
    this.address=address.parse(walletAddress);this.vault=address.parse(vault);
    requireValue(chainId===5042002,'circle_chain','Circle attestation is enabled only for Arc Testnet.',503);
    this.executable=executable;this.invoke=invoke;this.cliHome=cliHome;
  }
  async command(args) {
    try {
      const {stdout}=await this.invoke(this.executable,args,{timeout:75_000,maxBuffer:256_000,windowsHide:true,env:{...process.env,DO_NOT_TRACK:'1',...(this.cliHome?{CIRCLE_CLI_HOME:this.cliHome}:{})}});
      return JSON.parse(stdout).data;
    } catch {throw new ProductError('circle_unavailable','Circle Agent Wallet is unavailable. Check the installed CLI and its testnet login session.',503);}
  }
  async prepare() {
    const result=await this.command(['wallet','list','--chain','ARC-TESTNET','--type','agent','--output','json']);
    requireValue(Array.isArray(result?.wallets) && result.wallets.some(wallet=>wallet.type==='agent'
      && wallet.blockchain==='ARC-TESTNET' && wallet.address?.toLowerCase()===this.address.toLowerCase()),
      'circle_wallet','The configured attestor is not an authenticated Circle Agent Wallet on Arc Testnet.',503);
  }
  async signTypedData(document) {
    requireValue(document.primaryType==='ProofApproval' && document.domain.name==='ZeroKey Mate'
      && document.domain.version==='1' && Number(document.domain.chainId)===5042002
      && document.domain.verifyingContract.toLowerCase()===this.vault.toLowerCase(),
      'circle_scope','Circle can only attest a proof for this versioned vault deployment.',403);
    // Construct an allowlisted document: callers cannot send a private witness or arbitrary fields.
    const typed={domain:{name:'ZeroKey Mate',version:'1',chainId:5042002,verifyingContract:this.vault},primaryType:'ProofApproval',types:{
      EIP712Domain:[{name:'name',type:'string'},{name:'version',type:'string'},{name:'chainId',type:'uint256'},
        {name:'verifyingContract',type:'address'}],
      ProofApproval:[{name:'actionHash',type:'bytes32'},{name:'proofHash',type:'bytes32'}],
    },message:{actionHash:hash32.parse(document.message.actionHash),proofHash:hash32.parse(document.message.proofHash)}};
    const result=await this.command(['wallet','sign','typed-data',JSON.stringify(typed,(_,v)=>typeof v==='bigint'?String(v):v),
      '--address',this.address,'--chain','ARC-TESTNET','--output','json']);
    return signatureSchema.parse(result?.signature);
  }
}
