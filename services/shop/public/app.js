const $=id=>document.getElementById(id);
let loading=false;
async function check(){
  if(loading)return;loading=true;$('check-again').disabled=true;
  try{
    const response=await fetch('/api/catalog',{cache:'no-store'});
    if(!response.ok)throw new Error('unavailable');
    const catalog=await response.json();
    const product=catalog.products.find(product=>product.id==='mate-lager');
    if(!product)throw new Error('unavailable');
    $('price').textContent=(Number(product.amount)/1_000_000).toFixed(2);
    $('copy-request').disabled=!catalog.checkoutAvailable;
    $('copy-status').textContent=catalog.checkoutAvailable?'Say this to Mate, or copy it into your conversation.':'You can start with Mate when this shop is ready.';
    $('availability-title').textContent=catalog.checkoutAvailable?'Ready for Mate':'Checkout is being connected';
    $('availability-message').textContent=catalog.checkoutAvailable?'Ask Mate to start your order. Age verification comes before payment.':catalog.unavailableReason;
  }catch{
    $('copy-request').disabled=true;
    $('availability-title').textContent='The shop is temporarily unavailable';
    $('availability-message').textContent='No order or payment has been sent. You can check again here.';
  }finally{loading=false;$('check-again').disabled=false;}
}
$('copy-request').addEventListener('click',async()=>{
  try{await navigator.clipboard.writeText($('mate-request').value);$('copy-status').textContent='Copied. Paste this into your conversation with Mate.';}
  catch{$('mate-request').select();$('copy-status').textContent='Select and copy the request, or say it to Mate.';}
});
$('check-again').addEventListener('click',check);
check();
