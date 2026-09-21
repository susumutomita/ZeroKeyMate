const $=id=>document.getElementById(id);
let loading=false,catalog;
function showSelection(){
  const product=catalog?.products.find(product=>product.id===$('product-select').value);
  if(!product)return;
  const quantity=Number($('quantity-select').value),age=product.minimumAge>0;
  $('product-name').textContent=product.name;
  $('product-description').textContent=product.description;
  $('product-spec').textContent=product.size+(age?' · Ages 20+':' · No age check');
  $('price').textContent=(Number(product.amount)*quantity/1_000_000).toFixed(2);
  $('mate-request').value=`Buy me ${quantity} ${quantity===1?'bottle':'bottles'} of ${product.name}.`;
  $('can-kind').textContent=age?'LAGER':'SPARKLING';
  document.querySelector('.product').classList.toggle('water',!age);
  document.querySelector('.art').setAttribute('aria-label',`An illustration of ${product.name}`);
  $('availability-message').textContent=catalog.checkoutAvailable
    ? (age?'Ask Mate to start your order. Age verification comes before payment.':'Ask Mate to start your order. No card scan needed; approve the exact payment on your phone.')
    : catalog.unavailableReason;
  $('copy-status').textContent=catalog.checkoutAvailable?'Say this to Mate, or copy it into your conversation.':'You can start with Mate when this shop is ready.';
}
async function check(){
  if(loading)return;loading=true;$('check-again').disabled=true;
  try{
    const response=await fetch('/api/catalog',{cache:'no-store'});
    if(!response.ok)throw new Error('unavailable');
    catalog=await response.json();
    if(!catalog.products?.some(product=>product.id==='mate-lager'))throw new Error('unavailable');
    for(const option of $('product-select').options)option.disabled=!catalog.products.some(product=>product.id===option.value);
    if($('product-select').selectedOptions[0].disabled)$('product-select').value='mate-lager';
    $('product-select').disabled=false;$('quantity-select').disabled=false;
    $('copy-request').disabled=!catalog.checkoutAvailable;
    $('copy-status').textContent=catalog.checkoutAvailable?'Say this to Mate, or copy it into your conversation.':'You can start with Mate when this shop is ready.';
    $('availability-title').textContent=catalog.checkoutAvailable?'Ready for Mate':'Checkout is being connected';
    showSelection();
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
$('product-select').addEventListener('change',showSelection);
$('quantity-select').addEventListener('change',showSelection);
check();
