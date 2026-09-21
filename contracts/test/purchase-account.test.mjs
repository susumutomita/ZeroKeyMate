import {before, after, test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {spawn} from 'node:child_process';
import {createPublicClient, createWalletClient, http, hashTypedData, encodeAbiParameters, parseAbiParameters, parseSignature, keccak256, toHex, toFunctionSelector} from 'viem';
import {foundry} from 'viem/chains';
import {mnemonicToAccount} from 'viem/accounts';

// Public development accounts, usable only on this loopback Anvil test chain.
const accounts=Array.from({length:5},(_,addressIndex)=>mnemonicToAccount('test test test test test test test test test test test junk',{addressIndex}));
const [owner,agent,merchant,relayer,attacker]=accounts;
const rpc='http://127.0.0.1:8571';
const client=createPublicClient({chain:foundry,transport:http(rpc),pollingInterval:20});
const wallets=accounts.map(account=>createWalletClient({account,chain:foundry,transport:http(rpc)}));
const artifact=name=>JSON.parse(fs.readFileSync(new URL(`../../.build/contracts/${name}.json`,import.meta.url),'utf8'));
const tokenABI=artifact('TestAuthorizationToken');
const factoryABI=artifact('MatePurchaseAccountFactory');
const accountABI=artifact('MatePurchaseAccount');
const types={PurchasePermission:[{name:'owner',type:'address'},{name:'agent',type:'address'},{name:'merchant',type:'address'},{name:'maxPurchases',type:'uint32'},{name:'validUntil',type:'uint64'},{name:'salt',type:'bytes32'}]};
const transferTypes={TransferWithAuthorization:[{name:'from',type:'address'},{name:'to',type:'address'},{name:'value',type:'uint256'},{name:'validAfter',type:'uint256'},{name:'validBefore',type:'uint256'},{name:'nonce',type:'bytes32'}]};
let anvil,childError;
before(async()=>{
    anvil=spawn('anvil',['--host','127.0.0.1','--port','8571','--chain-id','31337','--silent'],{stdio:'ignore'});
    anvil.on('error',error=>{childError=error;});
    for(let i=0;i<100;i++) {
        if(childError) throw childError;
        if(anvil.exitCode !== null) throw new Error('Test Anvil exited');
        try {assert.equal(await client.getChainId(),31337);return;} catch {await new Promise(resolve=>setTimeout(resolve,100));}
    }
    throw new Error('Local test chain unavailable');
});
after(()=>anvil?.kill('SIGTERM'));
async function mined(hash) {const r=await client.waitForTransactionReceipt({hash});assert.equal(r.status,'success');return r;}
async function deploy(a,args=[]) {return mined(await wallets[0].deployContract({abi:a.abi,bytecode:a.bytecode,args}));}
async function call(address,a,functionName,args=[],wallet=wallets[3]) {
    const {request}=await client.simulateContract({address,abi:a.abi,functionName,args,account:wallet.account});
    return mined(await wallet.writeContract(request));
}
const read=(address,a,functionName,args=[])=>client.readContract({address,abi:a.abi,functionName,args});
async function fixture(balance=2_000_000n) {
    const token=(await deploy(tokenABI)).contractAddress;
    const deployment=await deploy(factoryABI,[token]);
    const factory=deployment.contractAddress;
    const now=(await client.getBlock()).timestamp;
    const p={owner:owner.address,agent:agent.address,merchant:merchant.address,maxPurchases:3,validUntil:now+3600n,salt:keccak256(toHex('public test salt'))};
    const domain={name:'ZeroKeyMate Purchase Permission',version:'1',chainId:31337,verifyingContract:factory};
    const signature=await owner.signTypedData({domain,types,primaryType:'PurchasePermission',message:p});
    const account=await read(factory,factoryABI,'predict',[p]);
    const created=await call(factory,factoryABI,'create',[p,signature]);
    await call(token,tokenABI,'mint',[account,balance]);
    return {token,factory,account,p,domain,signature,deploymentGas:deployment.gasUsed,creationGas:created.gasUsed};
}
async function payment(f,slot=0,changes={},signer=agent) {
    const now=(await client.getBlock()).timestamp;
    const nonce=slot<3?await read(f.account,accountABI,'slotNonce',[slot]):keccak256(toHex(`invalid ${slot}`));
    const p={from:f.account,to:merchant.address,value:100000n,validAfter:now-1n,validBefore:now+180n,nonce,...changes};
    const domain={name:'USDC',version:'2',chainId:31337,verifyingContract:f.token};
    const hash=hashTypedData({domain,types:transferTypes,primaryType:'TransferWithAuthorization',message:p});
    const s=parseSignature(await signer.signTypedData({domain,types:transferTypes,primaryType:'TransferWithAuthorization',message:p}));
    const blob=encodeAbiParameters(parseAbiParameters('address,address,uint256,uint256,uint256,bytes32,uint32,uint8,bytes32,bytes32'),[p.from,p.to,p.value,p.validAfter,p.validBefore,p.nonce,slot,Number(s.v??BigInt(27+s.yParity)),s.r,s.s]);
    return {p,hash,blob,args:[p.from,p.to,p.value,p.validAfter,p.validBefore,p.nonce,blob]};
}
test('three fixed slots enforce the total even with excess balance, replays and top-ups',async()=>{
    const f=await fixture();
    for(let slot=0;slot<3;slot++) {
        const p=await payment(f,slot);
        assert.equal(await read(f.account,accountABI,'isValidSignature',[p.hash,p.blob]),'0x1626ba7e');
        await call(f.token,tokenABI,'transferWithAuthorization',p.args);
        assert.equal(await read(f.token,tokenABI,'authorizationState',[f.account,p.p.nonce]),true);
        await assert.rejects(()=>call(f.token,tokenABI,'transferWithAuthorization',p.args),/NonceUsed/);
    }
    await call(f.token,tokenABI,'mint',[f.account,2_000_000n]);
    const changed=await payment(f,0);
    await assert.rejects(()=>call(f.token,tokenABI,'transferWithAuthorization',changed.args),/NonceUsed/);
    const excess=await payment(f,3);
    assert.equal(await read(f.account,accountABI,'isValidSignature',[excess.hash,excess.blob]),'0xffffffff');
    assert.equal(await read(f.token,tokenABI,'balanceOf',[merchant.address]),300000n);
    assert.equal(await read(f.token,tokenABI,'balanceOf',[f.account]),3_700_000n);
    console.log(`Local-only measured gas: factory+implementation ${f.deploymentGas}; clone ${f.creationGas}`);
});
test('changed recipients, amounts, from, nonce and agent cannot spend',async()=>{
    const f=await fixture();
    for(const change of [{to:attacker.address},{value:1n},{from:owner.address},{nonce:keccak256(toHex('outside slot'))}]) {
        const p=await payment(f,0,change);
        assert.equal(await read(f.account,accountABI,'isValidSignature',[p.hash,p.blob]),'0xffffffff');
    }
    const forged=await payment(f,0,{},attacker);
    assert.equal(await read(f.account,accountABI,'isValidSignature',[forged.hash,forged.blob]),'0xffffffff');
    const valid=await payment(f);
    assert.equal(await read(f.account,accountABI,'isValidSignature',[keccak256(toHex('other domain')),valid.blob]),'0xffffffff');
    assert.equal(await read(f.account,accountABI,'isValidSignature',[valid.hash,'0x1234']),'0xffffffff');
});
test('clone initialization is factory-only, sealed and idempotent across relayers',async()=>{
    const f=await fixture();
    const args=[owner.address,agent.address,merchant.address,3,f.p.validUntil];
    await assert.rejects(()=>call(f.account,accountABI,'initialize',args),/InvalidPermission/);
    const implementation=await read(f.factory,factoryABI,'implementation');
    await assert.rejects(()=>call(implementation,accountABI,'initialize',args),/InvalidPermission/);
    const p=await payment(f);
    await call(f.token,tokenABI,'transferWithAuthorization',p.args);
    await call(f.factory,factoryABI,'create',[f.p,f.signature],wallets[4]);
    assert.equal(await read(f.token,tokenABI,'authorizationState',[f.account,p.p.nonce]),true);
    assert.equal((await read(f.factory,factoryABI,'predict',[f.p])).toLowerCase(),f.account.toLowerCase());
    await assert.rejects(()=>call(f.factory,factoryABI,'create',[{...f.p,maxPurchases:4},f.signature]),/InvalidOwnerSignature/);
});
test('owner withdrawal revokes atomically, cannot be replayed and never pays another recipient',async()=>{
    const f=await fixture();
    const now=(await client.getBlock()).timestamp;
    const args={amount:2_000_000n,nonce:0n,expiresAt:now+120n};
    const domain={name:'ZeroKeyMate Purchase Account',version:'1',chainId:31337,verifyingContract:f.account};
    const types={Withdraw:[{name:'amount',type:'uint256'},{name:'nonce',type:'uint256'},{name:'expiresAt',type:'uint64'}]};
    const bad=await attacker.signTypedData({domain,types,primaryType:'Withdraw',message:args});
    await assert.rejects(()=>call(f.account,accountABI,'withdraw',[args.amount,args.nonce,args.expiresAt,bad]),/InvalidAdminAuthorization/);
    const signature=await owner.signTypedData({domain,types,primaryType:'Withdraw',message:args});
    await assert.rejects(()=>call(f.account,accountABI,'withdraw',[1n,args.nonce,args.expiresAt,signature]),/InvalidAdminAuthorization/);
    await assert.rejects(()=>call(f.account,accountABI,'revoke',[args.nonce,args.expiresAt,signature]),/InvalidAdminAuthorization/);
    await call(f.account,accountABI,'withdraw',[args.amount,args.nonce,args.expiresAt,signature]);
    assert.equal(await read(f.account,accountABI,'revoked'),true);
    assert.equal(await read(f.token,tokenABI,'balanceOf',[owner.address]),args.amount);
    assert.equal(await read(f.token,tokenABI,'balanceOf',[relayer.address]),0n);
    await assert.rejects(()=>call(f.account,accountABI,'withdraw',[args.amount,args.nonce,args.expiresAt,signature]),/InvalidAdminAuthorization/);
    await call(f.token,tokenABI,'mint',[f.account,1_000_000n]);
    await call(f.factory,factoryABI,'create',[f.p,f.signature],wallets[4]);
    const p=await payment(f);
    assert.equal(await read(f.account,accountABI,'isValidSignature',[p.hash,p.blob]),'0xffffffff');
});
test('insufficient funds leave the slot unused; authorization and permission expiries are enforced',async()=>{
    const f=await fixture(0n);
    const p=await payment(f);
    await assert.rejects(()=>call(f.token,tokenABI,'transferWithAuthorization',p.args),/ERC20InsufficientBalance/);
    assert.equal(await read(f.token,tokenABI,'authorizationState',[f.account,p.p.nonce]),false);
    await call(f.token,tokenABI,'mint',[f.account,100000n]);
    // Cross a block-time boundary deliberately: both endpoints must use the
    // same origin or a slow runner can shrink a 302-second window to 301.
    await client.request({method:'evm_increaseTime',params:[2]});
    await client.request({method:'evm_mine'});
    const tooLong=await payment(f,0,{validAfter:p.p.validAfter,validBefore:p.p.validAfter+302n});
    assert.equal(await read(f.account,accountABI,'isValidSignature',[tooLong.hash,tooLong.blob]),'0xffffffff');
    await call(f.token,tokenABI,'transferWithAuthorization',p.args);
    await client.request({method:'evm_increaseTime',params:[3601]});
    await client.request({method:'evm_mine'});
    const expired=await payment(f,1);
    assert.equal(await read(f.account,accountABI,'isValidSignature',[expired.hash,expired.blob]),'0xffffffff');
});


test('owner revocation binds account, nonce and expiry and blocks remaining payment slots',async()=>{
    const f=await fixture(),other=await fixture();
    const now=(await client.getBlock()).timestamp;
    const message={nonce:0n,expiresAt:now+120n};
    const domain={name:'ZeroKeyMate Purchase Account',version:'1',chainId:31337,verifyingContract:f.account};
    const revokeTypes={Revoke:[{name:'nonce',type:'uint256'},{name:'expiresAt',type:'uint64'}]};
    const sign=(values=message,d=domain)=>owner.signTypedData({domain:d,types:revokeTypes,primaryType:'Revoke',message:values});
    const signature=await sign();
    await assert.rejects(()=>call(other.account,accountABI,'revoke',[0n,message.expiresAt,signature]),/InvalidAdminAuthorization/);
    await assert.rejects(()=>call(f.account,accountABI,'revoke',[1n,message.expiresAt,signature]),/InvalidAdminAuthorization/);
    for(const expiresAt of [now,now+301n]) {
        const invalid=await sign({nonce:0n,expiresAt});
        await assert.rejects(()=>call(f.account,accountABI,'revoke',[0n,expiresAt,invalid]),/InvalidAdminAuthorization/);
    }
    const wrongChain=await sign(message,{...domain,chainId:5042002});
    await assert.rejects(()=>call(f.account,accountABI,'revoke',[0n,message.expiresAt,wrongChain]),/InvalidAdminAuthorization/);
    assert.equal(await read(f.account,accountABI,'adminNonce'),0n);
    await call(f.account,accountABI,'revoke',[0n,message.expiresAt,signature]);
    assert.equal(await read(f.account,accountABI,'revoked'),true);
    assert.equal(await read(f.account,accountABI,'adminNonce'),1n);
    await assert.rejects(()=>call(f.account,accountABI,'revoke',[0n,message.expiresAt,signature]),/InvalidAdminAuthorization/);
    const p=await payment(f,2);
    await assert.rejects(()=>call(f.token,tokenABI,'transferWithAuthorization',p.args),/InvalidSignature/);
    assert.equal(await read(f.token,tokenABI,'balanceOf',[merchant.address]),0n);
});

test('permission signatures bind every delegation field and the factory domain',async()=>{
    const f=await fixture(),other=await fixture();
    for(const changes of [{owner:attacker.address},{agent:attacker.address},{merchant:attacker.address},
        {maxPurchases:4},{validUntil:f.p.validUntil+1n},{salt:keccak256(toHex('another permission'))}]) {
        await assert.rejects(()=>call(f.factory,factoryABI,'create',[{...f.p,...changes},f.signature]),/InvalidOwnerSignature/);
    }
    await assert.rejects(()=>call(other.factory,factoryABI,'create',[f.p,f.signature]),/InvalidOwnerSignature/);
    for(const changes of [{maxPurchases:0},{maxPurchases:101},{agent:owner.address},
        {merchant:'0x0000000000000000000000000000000000000000'},{validUntil:1n},
        {validUntil:(await client.getBlock()).timestamp+86401n}]) {
        const p={...f.p,...changes};
        const signature=await owner.signTypedData({domain:f.domain,types,primaryType:'PurchasePermission',message:p});
        await assert.rejects(()=>call(f.factory,factoryABI,'create',[p,signature]),new RegExp('InvalidPermission|'+toFunctionSelector('InvalidPermission()')));
    }
});

test('malformed ABI words and invalid time windows cannot consume a payment slot',async()=>{
    const f=await fixture();
    const valid=await payment(f);
    for(const word of [0,6,7]) {
        const bytes=Buffer.from(valid.blob.slice(2),'hex');bytes[word*32]=1;
        const args=[...valid.args];args[6]='0x'+bytes.toString('hex');
        await assert.rejects(()=>call(f.token,tokenABI,'transferWithAuthorization',args),/InvalidSignature/);
    }
    const now=(await client.getBlock()).timestamp;
    for(const changes of [{validAfter:now+1n},{validBefore:now},{validBefore:f.p.validUntil+1n}]) {
        const p=await payment(f,0,changes);
        assert.equal(await read(f.account,accountABI,'isValidSignature',[p.hash,p.blob]),'0xffffffff');
    }
    assert.equal(await read(f.token,tokenABI,'authorizationState',[f.account,valid.p.nonce]),false);
    await call(f.token,tokenABI,'transferWithAuthorization',valid.args);
    assert.equal(await read(f.token,tokenABI,'balanceOf',[merchant.address]),100000n);
});
