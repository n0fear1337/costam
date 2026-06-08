let listings=[],myItems=[],myListings=[];
let vehicleListings=[],myVehicles=[],myVehicleListings=[];
let durations=[],taxRate=0.05,vehicleTaxRate=0.05;
let maxListings=5,maxVehicleListings=3;
let minPrice=10,maxPrice=10000000,vehicleMinPrice=1000,vehicleMaxPrice=50000000;
let playerCoins=0;

let selectedBuyListing=null,selectedBuyType='item';
let selectedSellItem=null,selectedSellVehicle=null;
let selectedDuration=null,selectedDurationVeh=null;
let selectedCurrency='money',selectedCurrencyVeh='money';
let currentVehiclePhoto=null;

const app=document.getElementById('app');
const searchInput=document.getElementById('searchInput');

function itemIcon(name){return `nui://es_extended/html/img/items/${name}.png`}
function itemIconHtml(name){return `<img src="${itemIcon(name)}" onerror="this.style.display='none';this.nextElementSibling.style.display='flex'" style="width:100%;height:100%;object-fit:contain"><div class="icon-fallback" style="display:none"><i class="fas fa-box"></i></div>`}

function priceHtml(price,currency){
    if(currency==='coins') return `<div class="coin-circle-sm">C</div>${Number(price).toLocaleString('pl-PL')}`;
    return `<i class="fas fa-dollar-sign"></i>${Number(price).toLocaleString('pl-PL')}`;
}
function priceClass(currency){return currency==='coins'?'price-coins':'price-money'}
function formatMoney(a,c){
    if(c==='coins') return Number(a).toLocaleString('pl-PL')+' C';
    return '$'+Number(a).toLocaleString('pl-PL');
}
function formatTimeLeft(s){
    if(s<=0)return'Wygaslo';if(s<60)return s+'s';if(s<3600)return Math.floor(s/60)+'min';
    if(s<86400)return Math.floor(s/3600)+'h '+Math.floor((s%3600)/60)+'min';
    return Math.floor(s/86400)+'d '+Math.floor((s%86400)/3600)+'h';
}
function escapeHtml(t){const d=document.createElement('div');d.textContent=t;return d.innerHTML}
function copyToClipboard(t){const a=document.createElement('textarea');a.value=t;a.style.position='fixed';a.style.left='-9999px';document.body.appendChild(a);a.select();document.execCommand('copy');document.body.removeChild(a)}
function showCopied(el){el.classList.add('copied');const o=el.innerHTML;el.innerHTML='<i class="fas fa-check"></i> Skopiowano!';setTimeout(()=>{el.innerHTML=o;el.classList.remove('copied')},1500)}

function compressImage(b64,mw,mh,q){return new Promise(r=>{mw=mw||640;mh=mh||360;q=q||0.35;const i=new Image();i.onload=function(){const c=document.createElement('canvas');let w=i.width,h=i.height;if(w>mw){h=Math.round(h*mw/w);w=mw}if(h>mh){w=Math.round(w*mh/h);h=mh}c.width=w;c.height=h;c.getContext('2d').drawImage(i,0,0,w,h);r(c.toDataURL('image/jpeg',q))};i.onerror=()=>r(null);i.src=b64})}

function openLightbox(s){document.getElementById('lightboxImg').src=s;document.getElementById('photoLightbox').classList.remove('hidden')}
function closeLightbox(){document.getElementById('photoLightbox').classList.add('hidden');document.getElementById('lightboxImg').src=''}

function buildSellerHtml(name,discordId){
    let h=`<div class="listing-card-seller">${escapeHtml(name)}</div>`;
    if(discordId)h+=`<div class="listing-card-discord" data-discord="${escapeHtml(discordId)}" title="Kliknij aby skopiowac"><i class="fab fa-discord"></i> ${escapeHtml(discordId)}</div>`;
    return h;
}
function attachDiscordCopy(c){c.querySelectorAll('.listing-card-discord').forEach(el=>{el.addEventListener('click',e=>{e.stopPropagation();copyToClipboard(el.dataset.discord);showCopied(el)})})}

document.querySelectorAll('.nav-link').forEach(l=>{l.addEventListener('click',()=>{document.querySelectorAll('.nav-link').forEach(x=>x.classList.remove('active'));l.classList.add('active');const t=l.dataset.tab;['browseTab','vehiclesTab','sellTab','mylistingsTab'].forEach(id=>{document.getElementById(id).classList.toggle('hidden',id!==t+'Tab')});document.getElementById('searchBox').style.display=(t==='browse'||t==='vehicles')?'flex':'none'})});
document.querySelectorAll('.sell-subtab').forEach(b=>{b.addEventListener('click',()=>{document.querySelectorAll('.sell-subtab').forEach(x=>x.classList.remove('active'));b.classList.add('active');const s=b.dataset.sub;document.getElementById('sellItemsSection').classList.toggle('hidden',s!=='items');document.getElementById('sellVehiclesSection').classList.toggle('hidden',s!=='sellvehicles')})});

document.getElementById('closeBtn').addEventListener('click',closeApp);
document.addEventListener('keydown',e=>{if(e.key==='Escape'&&!app.classList.contains('hidden')){const lb=document.getElementById('photoLightbox');if(!lb.classList.contains('hidden')){closeLightbox();return}for(const id of['buyModal','sellModal','sellVehicleModal']){if(!document.getElementById(id).classList.contains('hidden')){document.getElementById(id).classList.add('hidden');return}}closeApp()}});
function closeApp(){app.classList.add('hidden');fetch('https://lunatic-rynek/closeMenu',{method:'POST',body:'{}'})}

document.getElementById('refreshBtn').addEventListener('click',()=>{document.getElementById('refreshBtn').classList.add('spinning');setTimeout(()=>document.getElementById('refreshBtn').classList.remove('spinning'),600);refreshAll()});
searchInput.addEventListener('input',()=>{renderListings();renderVehicleListings()});

function renderListings(){
    const q=searchInput.value.toLowerCase().trim();
    let f=q?listings.filter(l=>l.itemLabel.toLowerCase().includes(q)||l.sellerName.toLowerCase().includes(q)):listings;
    const g=document.getElementById('listingsGrid');g.innerHTML='';
    document.getElementById('emptyBrowse').classList.toggle('hidden',f.length>0);
    f.forEach(l=>{
        const c=document.createElement('div');c.className='listing-card';
        c.innerHTML=`<div class="listing-card-top"><div class="listing-card-icon item-icon">${itemIconHtml(l.itemName)}</div><div class="listing-card-info"><div class="listing-card-name">${escapeHtml(l.itemLabel)}</div><div class="listing-card-count">${l.count}x</div></div></div><div class="listing-card-bottom"><div class="listing-card-price ${priceClass(l.currencyType)}">${priceHtml(l.price,l.currencyType)}</div><div class="listing-card-meta">${buildSellerHtml(l.sellerName,l.sellerDiscord)}<div class="listing-card-time"><i class="fas fa-clock"></i> ${formatTimeLeft(l.timeLeft)}</div></div></div>`;
        c.addEventListener('click',()=>openBuyModal(l,'item'));g.appendChild(c);
    });
    attachDiscordCopy(g);
}

function renderVehicleListings(){
    const q=searchInput.value.toLowerCase().trim();
    let f=q?vehicleListings.filter(l=>l.vehicleLabel.toLowerCase().includes(q)||l.plate.toLowerCase().includes(q)):vehicleListings;
    const g=document.getElementById('vehicleListingsGrid');g.innerHTML='';
    document.getElementById('emptyVehicles').classList.toggle('hidden',f.length>0);
    f.forEach(l=>{
        const c=document.createElement('div');c.className='listing-card vehicle-card'+(l.photo?' has-photo':'');
        const ph=l.photo?`<div class="listing-card-photo"><img src="${l.photo}"><div class="photo-zoom-hint"><i class="fas fa-search-plus"></i> Kliknij aby powiększyć</div></div>`:'';
        c.innerHTML=`${ph}<div class="listing-card-top"><div class="listing-card-icon veh"><i class="fas fa-car"></i></div><div class="listing-card-info"><div class="listing-card-name">${escapeHtml(l.vehicleLabel)}</div><div class="listing-card-count"><i class="fas fa-id-badge"></i> ${escapeHtml(l.plate)}</div></div></div><div class="listing-card-bottom"><div class="listing-card-price ${priceClass(l.currencyType)}">${priceHtml(l.price,l.currencyType)}</div><div class="listing-card-meta">${buildSellerHtml(l.sellerName,l.sellerDiscord)}<div class="listing-card-time"><i class="fas fa-clock"></i> ${formatTimeLeft(l.timeLeft)}</div></div></div>`;
        if(l.photo){c.querySelector('.listing-card-photo').addEventListener('click',e=>{e.stopPropagation();openLightbox(l.photo)})}
        c.addEventListener('click',()=>openBuyModal(l,'vehicle'));g.appendChild(c);
    });
    attachDiscordCopy(g);
}

function renderSellItems(){
    const g=document.getElementById('sellItemsGrid');g.innerHTML='';
    document.getElementById('emptyInventory').classList.toggle('hidden',myItems.length>0);
    myItems.forEach(item=>{
        const c=document.createElement('div');c.className='sell-item-card';
        c.innerHTML=`<div class="sell-item-card-icon item-icon">${itemIconHtml(item.name)}</div><div class="sell-item-card-info"><div class="sell-item-card-name">${escapeHtml(item.label)}</div><div class="sell-item-card-count">${item.count}x</div></div>`;
        c.addEventListener('click',()=>openSellModal(item));g.appendChild(c);
    });
}
function renderSellVehicles(){
    const g=document.getElementById('sellVehiclesGrid');g.innerHTML='';
    document.getElementById('emptyVehiclesInv').classList.toggle('hidden',myVehicles.length>0);
    myVehicles.forEach(v=>{
        const c=document.createElement('div');c.className='sell-item-card vehicle-sell-card';
        c.innerHTML=`<div class="sell-item-card-icon veh"><i class="fas fa-car"></i></div><div class="sell-item-card-info"><div class="sell-item-card-name">${escapeHtml(v.label)}</div><div class="sell-item-card-count"><i class="fas fa-id-badge"></i> ${escapeHtml(v.plate)}</div></div><div class="sell-item-card-camera"><i class="fas fa-camera"></i></div>`;
        c.addEventListener('click',()=>{fetch('https://lunatic-rynek/startPhotoMode',{method:'POST',body:JSON.stringify({vehicle:v})})});g.appendChild(c);
    });
}

function renderMyListings(){
    const g=document.getElementById('myListingsGrid');g.innerHTML='';
    document.getElementById('emptyMyListings').classList.toggle('hidden',myListings.length>0);
    myListings.forEach(l=>{
        const c=document.createElement('div');c.className='my-listing-card';
        c.innerHTML=`<div class="my-listing-top"><div class="my-listing-icon item-icon">${itemIconHtml(l.itemName)}</div><div class="my-listing-info"><div class="my-listing-name">${escapeHtml(l.itemLabel)}</div><div class="my-listing-detail">${l.count}x</div></div></div><div class="my-listing-bottom"><div class="my-listing-price ${priceClass(l.currencyType)}">${priceHtml(l.price,l.currencyType)}</div><div class="my-listing-time"><i class="fas fa-clock"></i> ${formatTimeLeft(l.timeLeft)}</div><button class="btn-cancel"><i class="fas fa-times"></i> Anuluj</button></div>`;
        c.querySelector('.btn-cancel').addEventListener('click',e=>{e.stopPropagation();cancelListing(l.id)});g.appendChild(c);
    });
}
function renderMyVehicleListings(){
    const g=document.getElementById('myVehicleListingsGrid');g.innerHTML='';
    document.getElementById('emptyMyVehListings').classList.toggle('hidden',myVehicleListings.length>0);
    myVehicleListings.forEach(l=>{
        const c=document.createElement('div');c.className='my-listing-card vehicle-listing';
        const th=l.photo?`<img class="my-listing-thumb" src="${l.photo}">`:'';
        c.innerHTML=`<div class="my-listing-top"><div class="my-listing-icon veh"><i class="fas fa-car"></i></div><div class="my-listing-info"><div class="my-listing-name">${escapeHtml(l.vehicleLabel)}</div><div class="my-listing-detail"><i class="fas fa-id-badge"></i> ${escapeHtml(l.plate)}</div></div>${th}</div><div class="my-listing-bottom"><div class="my-listing-price ${priceClass(l.currencyType)}">${priceHtml(l.price,l.currencyType)}</div><div class="my-listing-time"><i class="fas fa-clock"></i> ${formatTimeLeft(l.timeLeft)}</div><button class="btn-cancel"><i class="fas fa-times"></i> Anuluj</button></div>`;
        c.querySelector('.btn-cancel').addEventListener('click',e=>{e.stopPropagation();cancelVehicleListing(l.id)});g.appendChild(c);
    });
}

function openBuyModal(l,type){
    selectedBuyListing=l;selectedBuyType=type;const isV=type==='vehicle';
    document.getElementById('buyIcon').innerHTML=isV?'<i class="fas fa-car"></i>':(l.itemName?itemIconHtml(l.itemName):'<i class="fas fa-box"></i>');
    document.getElementById('buyIcon').className='buy-item-icon'+(isV?' veh':' item-icon');
    document.getElementById('buyItemName').textContent=isV?l.vehicleLabel:l.itemLabel;
    document.getElementById('buyItemCount').textContent=isV?('Tablica: '+l.plate):(l.count+'x');
    document.getElementById('buyItemSeller').textContent='Sprzedajacy: '+l.sellerName;
    const de=document.getElementById('buyItemDiscord');
    if(l.sellerDiscord){de.innerHTML=`<i class="fab fa-discord"></i> ${escapeHtml(l.sellerDiscord)}`;de.classList.remove('hidden');de.onclick=e=>{e.stopPropagation();copyToClipboard(l.sellerDiscord);showCopied(de)}}else{de.classList.add('hidden')}
    const curr=l.currencyType||'money';
    document.getElementById('buyPrice').textContent=formatMoney(l.price,curr);
    document.getElementById('buyPriceRow').className='buy-price-row '+(curr==='coins'?'coins-row':'');
    const pw=document.getElementById('buyPhotoWrap');
    if(isV&&l.photo){document.getElementById('buyPhoto').src=l.photo;pw.classList.remove('hidden');pw.onclick=e=>{e.stopPropagation();openLightbox(l.photo)}}else{pw.classList.add('hidden');pw.onclick=null}
    document.getElementById('buyModal').classList.remove('hidden');
}
document.getElementById('buyModalClose').addEventListener('click',()=>document.getElementById('buyModal').classList.add('hidden'));
document.getElementById('buyCancel').addEventListener('click',()=>document.getElementById('buyModal').classList.add('hidden'));
document.getElementById('buyConfirm').addEventListener('click',()=>{
    if(!selectedBuyListing)return;const b=document.getElementById('buyConfirm');b.disabled=true;
    fetch('https://lunatic-rynek/'+(selectedBuyType==='vehicle'?'buyVehicle':'buyItem'),{method:'POST',body:JSON.stringify({listingId:selectedBuyListing.id})}).then(r=>r.json()).then(()=>{b.disabled=false;document.getElementById('buyModal').classList.add('hidden');refreshAll()});
});

function setupCurrencyToggle(containerId,onChange){
    const c=document.getElementById(containerId);
    c.querySelectorAll('.curr-btn').forEach(b=>{b.addEventListener('click',()=>{c.querySelectorAll('.curr-btn').forEach(x=>x.classList.remove('active'));b.classList.add('active');onChange(b.dataset.curr)})});
}

function openSellModal(item){
    selectedSellItem=item;selectedCurrency='money';
    selectedDuration=durations.length>0?durations[0].seconds:3600;
    document.getElementById('sellItemName').textContent=item.label;
    document.getElementById('sellItemAvailable').textContent='Dostepne: '+item.count;
    document.getElementById('sellItemIcon').innerHTML=itemIconHtml(item.name);
    document.getElementById('sellItemIcon').className='sell-item-icon item-icon';
    document.getElementById('sellCount').value=1;document.getElementById('sellCount').max=item.count;
    document.getElementById('sellPrice').value=100;
    document.getElementById('taxPercent').textContent=Math.round(taxRate*100);
    document.getElementById('sellMaxBtn').onclick=()=>{document.getElementById('sellCount').value=item.count};
    document.querySelectorAll('#currencyToggle .curr-btn').forEach(b=>b.classList.toggle('active',b.dataset.curr==='money'));
    selectedCurrency='money';
    setupCurrencyToggle('currencyToggle',c=>{selectedCurrency=c;updateSellSummary()});
    buildDurationBtns('durationGrid',d=>{selectedDuration=d},selectedDuration);
    updateSellSummary();
    document.getElementById('sellModal').classList.remove('hidden');
}
document.getElementById('sellPrice').addEventListener('input',updateSellSummary);
function updateSellSummary(){
    const p=parseInt(document.getElementById('sellPrice').value)||0;
    const sym=selectedCurrency==='coins'?' C':'$';
    document.getElementById('taxValue').textContent='-'+(selectedCurrency==='coins'?'':sym)+Math.floor(p*taxRate).toLocaleString('pl-PL')+(selectedCurrency==='coins'?' C':'');
    document.getElementById('earningsValue').textContent=(selectedCurrency==='coins'?'':sym)+(p-Math.floor(p*taxRate)).toLocaleString('pl-PL')+(selectedCurrency==='coins'?' C':'');
}
document.getElementById('sellModalClose').addEventListener('click',()=>document.getElementById('sellModal').classList.add('hidden'));
document.getElementById('sellCancel').addEventListener('click',()=>document.getElementById('sellModal').classList.add('hidden'));
document.getElementById('sellConfirm').addEventListener('click',()=>{
    if(!selectedSellItem||!selectedDuration)return;
    const count=parseInt(document.getElementById('sellCount').value)||0;
    const price=parseInt(document.getElementById('sellPrice').value)||0;
    if(count<1||price<minPrice||price>maxPrice)return;
    const b=document.getElementById('sellConfirm');b.disabled=true;
    fetch('https://lunatic-rynek/listItem',{method:'POST',body:JSON.stringify({itemName:selectedSellItem.name,count,price,duration:selectedDuration,currencyType:selectedCurrency})}).then(r=>r.json()).then(()=>{b.disabled=false;document.getElementById('sellModal').classList.add('hidden');refreshAll()});
});

function openSellVehicleModal(v,photo){
    selectedSellVehicle=v;currentVehiclePhoto=photo||null;selectedCurrencyVeh='money';
    selectedDurationVeh=durations.length>0?durations[0].seconds:3600;
    document.getElementById('sellVehName').textContent=v.label;
    document.getElementById('sellVehPlate').textContent='Tablica: '+v.plate;
    document.getElementById('sellVehPrice').value=50000;
    document.getElementById('vehTaxPercent').textContent=Math.round(vehicleTaxRate*100);
    if(photo){document.getElementById('sellPhotoImg').src=photo;document.getElementById('sellPhotoPreview').classList.remove('hidden')}else{document.getElementById('sellPhotoPreview').classList.add('hidden')}
    document.querySelectorAll('#currencyToggleVeh .curr-btn').forEach(b=>b.classList.toggle('active',b.dataset.curr==='money'));
    selectedCurrencyVeh='money';
    setupCurrencyToggle('currencyToggleVeh',c=>{selectedCurrencyVeh=c;updateVehSellSummary()});
    buildDurationBtns('durationGridVeh',d=>{selectedDurationVeh=d},selectedDurationVeh);
    updateVehSellSummary();
    document.getElementById('sellVehicleModal').classList.remove('hidden');
}
document.getElementById('sellVehPrice').addEventListener('input',updateVehSellSummary);
function updateVehSellSummary(){
    const p=parseInt(document.getElementById('sellVehPrice').value)||0;
    const sym=selectedCurrencyVeh==='coins'?' C':'$';
    document.getElementById('vehTaxValue').textContent='-'+(selectedCurrencyVeh==='coins'?'':sym)+Math.floor(p*vehicleTaxRate).toLocaleString('pl-PL')+(selectedCurrencyVeh==='coins'?' C':'');
    document.getElementById('vehEarningsValue').textContent=(selectedCurrencyVeh==='coins'?'':sym)+(p-Math.floor(p*vehicleTaxRate)).toLocaleString('pl-PL')+(selectedCurrencyVeh==='coins'?' C':'');
}
document.getElementById('sellVehModalClose').addEventListener('click',()=>document.getElementById('sellVehicleModal').classList.add('hidden'));
document.getElementById('sellVehCancel').addEventListener('click',()=>document.getElementById('sellVehicleModal').classList.add('hidden'));
document.getElementById('sellVehConfirm').addEventListener('click',()=>{
    if(!selectedSellVehicle||!selectedDurationVeh)return;
    const price=parseInt(document.getElementById('sellVehPrice').value)||0;
    if(price<vehicleMinPrice||price>vehicleMaxPrice)return;
    const b=document.getElementById('sellVehConfirm');b.disabled=true;
    const up=currentVehiclePhoto?fetch('https://lunatic-rynek/uploadVehiclePhoto',{method:'POST',body:JSON.stringify({photo:currentVehiclePhoto})}):Promise.resolve();
    up.then(()=>new Promise(r=>setTimeout(r,200))).then(()=>fetch('https://lunatic-rynek/listVehicle',{method:'POST',body:JSON.stringify({plate:selectedSellVehicle.plate,price,duration:selectedDurationVeh,currencyType:selectedCurrencyVeh})})).then(r=>r.json()).then(()=>{b.disabled=false;document.getElementById('sellVehicleModal').classList.add('hidden');currentVehiclePhoto=null;refreshAll()});
});

function cancelListing(id){fetch('https://lunatic-rynek/cancelListing',{method:'POST',body:JSON.stringify({listingId:id})}).then(r=>r.json()).then(()=>refreshAll())}
function cancelVehicleListing(id){fetch('https://lunatic-rynek/cancelVehicleListing',{method:'POST',body:JSON.stringify({listingId:id})}).then(r=>r.json()).then(()=>refreshAll())}

function buildDurationBtns(cid,onSel,def){const g=document.getElementById(cid);g.innerHTML='';durations.forEach(d=>{const b=document.createElement('button');b.className='duration-btn'+(d.seconds===def?' active':'');b.textContent=d.label;b.addEventListener('click',()=>{g.querySelectorAll('.duration-btn').forEach(x=>x.classList.remove('active'));b.classList.add('active');onSel(d.seconds)});g.appendChild(b)})}

function refreshAll(){fetch('https://lunatic-rynek/refreshListings',{method:'POST',body:'{}'}).then(r=>r.json()).then(d=>{listings=d.listings||[];myListings=d.myListings||[];myItems=d.myItems||[];vehicleListings=d.vehicleListings||[];myVehicles=d.myVehicles||[];myVehicleListings=d.myVehicleListings||[];playerCoins=d.coins||0;document.getElementById('coinBalance').textContent=playerCoins;renderAll()})}
function renderAll(){renderListings();renderVehicleListings();renderSellItems();renderSellVehicles();renderMyListings();renderMyVehicleListings()}

window.addEventListener('message',function(ev){
    const d=ev.data;
    switch(d.type){
        case 'openMenu':
            listings=d.listings||[];myItems=d.myItems||[];myListings=d.myListings||[];
            vehicleListings=d.vehicleListings||[];myVehicles=d.myVehicles||[];myVehicleListings=d.myVehicleListings||[];
            durations=d.durations||[];taxRate=d.tax||0.05;vehicleTaxRate=d.vehicleTax||0.05;
            maxListings=d.maxListings||5;maxVehicleListings=d.maxVehicleListings||3;
            minPrice=d.minPrice||10;maxPrice=d.maxPrice||10000000;
            vehicleMinPrice=d.vehicleMinPrice||1000;vehicleMaxPrice=d.vehicleMaxPrice||50000000;
            playerCoins=d.coins||0;document.getElementById('coinBalance').textContent=playerCoins;
            document.querySelectorAll('.nav-link').forEach(l=>l.classList.remove('active'));
            document.querySelector('.nav-link[data-tab="browse"]').classList.add('active');
            ['browseTab','vehiclesTab','sellTab','mylistingsTab'].forEach(id=>{document.getElementById(id).classList.toggle('hidden',id!=='browseTab')});
            document.getElementById('searchBox').style.display='flex';searchInput.value='';
            document.querySelectorAll('.sell-subtab').forEach(b=>b.classList.remove('active'));
            document.querySelector('.sell-subtab[data-sub="items"]').classList.add('active');
            document.getElementById('sellItemsSection').classList.remove('hidden');
            document.getElementById('sellVehiclesSection').classList.add('hidden');
            renderAll();app.classList.remove('hidden');break;
        case 'hideForPhoto':app.classList.add('hidden');break;
        case 'showPhotoHud':document.getElementById('photoHud').classList.remove('hidden');break;
        case 'hidePhotoHud':document.getElementById('photoHud').classList.add('hidden');break;
        case 'openSellVehicleWithPhoto':
            app.classList.remove('hidden');
            if(d.photo){compressImage(d.photo,640,360,0.35).then(c=>openSellVehicleModal(d.vehicle,c))}
            else openSellVehicleModal(d.vehicle,null);break;
    }
});

setInterval(()=>{if(app.classList.contains('hidden'))return;listings.forEach(l=>{if(l.timeLeft>0)l.timeLeft--});myListings.forEach(l=>{if(l.timeLeft>0)l.timeLeft--});vehicleListings.forEach(l=>{if(l.timeLeft>0)l.timeLeft--});myVehicleListings.forEach(l=>{if(l.timeLeft>0)l.timeLeft--})},1000);
