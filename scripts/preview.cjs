// Local demonstration using the production component/template, with mocked services.
// NODE_PATH=<dev deps>/node_modules node scripts/preview.cjs <output directory>
const fs = require('node:fs');
const path = require('node:path');
const sass = require('sass');
const Handlebars = require('handlebars');
const { Preprocessor } = require('content-tag');
const { preprocess } = require('@glimmer/syntax');
const root = path.resolve(__dirname, '..');
const out = process.argv[2];
if (!out) throw new Error('Provide a preview output directory.');
const source = fs.readFileSync(path.join(root, 'assets/javascripts/discourse/components/westan-points/hub.gjs'), 'utf8');
new Preprocessor().process(source, { filename: 'hub.gjs' });
const templateSource = source.match(/<template>([\s\S]*)<\/template>/)[1];
preprocess(templateSource);
const template = templateSource.replaceAll('@configMode', 'this.args.configMode').replaceAll('this.', '@root.').replace(/=(\{\{[^}]+\}\})/g, '="$1"');
const component = source.split('<template>')[0].replace(/^import .*;$/gm, '').replace(/@(?:tracked|action|service)\s*/g, '').replace('export default class', 'class') + '}';
const css = sass.compile(path.join(root, 'assets/stylesheets/westan-points/points.scss')).css;
fs.mkdirSync(out, { recursive: true });
fs.writeFileSync(path.join(out, 'points.css'), css);
fs.writeFileSync(path.join(out, 'handlebars.js'), fs.readFileSync(require.resolve('handlebars/dist/handlebars.runtime.min.js')));
const icons = {
 'paper-plane':'m21 3-7 18-4-7-7-4 18-7ZM10 14 21 3',
 'clock-rotate-left':'M3 10a9 9 0 1 1 1 7M3 3v7h7m2-4v6l4 2',
 'circle-info':'M12 11v6m0-10v1M22 12a10 10 0 1 1-20 0 10 10 0 0 1 20 0',
 'gift':'M3 8h18v4H3zm2 4v9h14v-9M12 8v13M12 8C2 8 6-2 12 8c6-10 10 0 0 0',
 'coins':'M20 7c0 3-16 3-16 0s16-3 16 0Zm-16 0v10c0 3 16 3 16 0V7M4 12c0 3 16 3 16 0',
 'check':'m5 12 4 4L19 6', 'xmark':'m6 6 12 12M6 18 18 6', 'plus':'M12 4v16M4 12h16',
 'gear':'M9 3h6l1 3 3 1 2 5-2 5-3 1-1 3H9l-1-3-3-1-2-5 2-5 3-1 1-3ZM15 12a3 3 0 1 1-6 0 3 3 0 0 1 6 0',
 'arrow-up':'M12 20V4m-7 7 7-7 7 7','arrow-down':'M12 4v16m-7-7 7 7 7-7',
};
const script = `
const params = new URLSearchParams(location.search);
document.documentElement.dataset.theme = params.get('theme') || 'light';
const configMode = params.get('config') === '1';
const avatar = name => 'data:image/svg+xml,'+encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="96" height="96"><rect width="96" height="96" rx="48" fill="#dec5ee"/><text x="48" y="62" text-anchor="middle" fill="#301a40" font-family="sans-serif" font-size="34">'+name+'</text></svg>');
const state = { can_manage:true, is_multiplier_eligible:true, wallet:{balance:998,lifetime_earned:2012,next_expiration:{amount:194,expires_at:'2026-10-01T03:00:00Z'}},rules:{points_per_post:1,points_per_topic:2,vip_multiplier:2},
 transactions:[{id:1,description:'Recebido de @Andreza',amount:120,origin:'member',counterparty_username:'Andreza',note:'Obrigada pela ajuda!',created_at:'2026-09-19T15:30:00Z'},{id:2,description:'Post publicado',amount:2,origin:'system',created_at:'2026-09-19T14:18:00Z'}],
 rewards:[{id:1,title:'7 dias de VIP',description:'VIP por uma semana.',cost:300,stock:null,can_redeem:true,enabled:true,reward_type:'vip_group_access',duration_days:7,automatic_fulfillment:true}],redemptions:[],admin:{rewards:[],redemptions:[]} };
state.admin.rewards = state.rewards.map(x=>({...x}));
const people = [{id:2,username:'Andreza',name:'Andreza',avatar_template:avatar('A')},{id:3,username:'Naruto',name:'Naruto Geek',avatar_template:avatar('N')},{id:4,username:'Blair',name:'Blair',avatar_template:avatar('B')}];
let failure = false;
const completed = new Map();
const clone = value => JSON.parse(JSON.stringify(value));
class Component { constructor(args){this.args=args;} willDestroy(){} }
const extractError = error => error.jqXHR?.responseJSON?.errors?.join(' ') || error.message;
const popupAjaxError = error => alert(extractError(error));
async function userSearch({term}) { await new Promise(resolve=>setTimeout(resolve,180)); return people.filter(person=>(person.username+' '+person.name).toLowerCase().includes(term.toLowerCase())); }
async function ajax(url, options={}) {
 await new Promise(resolve=>setTimeout(resolve,180));
 if (url.endsWith('/transfer')) {
   const data=options.data;
   if (!completed.has(data.request_id)) {
     if(data.amount>state.wallet.balance) throw {jqXHR:{status:422,responseJSON:{errors:['Saldo insuficiente.']}}};
     state.wallet.balance-=data.amount;
     state.transactions.unshift({id:Date.now(),description:'Enviado para @'+data.username,amount:-data.amount,origin:'member',counterparty_username:data.username,note:data.description,created_at:new Date().toISOString()});
     completed.set(data.request_id,clone(state.transactions[0]));
   }
   if(failure){failure=false;throw {jqXHR:{status:0}};}
   return {wallet:clone(state.wallet),transaction:clone(completed.get(data.request_id))};
 }
 if(url.includes('/admin/rewards')) {
   const reward={...options.data,cost:Number(options.data.cost),id:options.type==='PATCH'?Number(url.split('/').at(-1)):Date.now()};
   state.admin.rewards=state.admin.rewards.filter(item=>item.id!==reward.id).concat(reward);
   return {reward};
 }
 if(url.endsWith('/admin/config')) return {can_manage:true,admin:clone(state.admin)};
 if(url.endsWith('/transactions'))return {transactions:clone(state.transactions)};
 return clone(state);
}
${component}
const hub = new WestanPointsHub({model:clone(state),configMode});
hub.currentUser={id:1,name:'Nugget',username:'Nugget',admin:true,avatar_template:avatar('N')};
hub.router={transitionTo(route){location.href='?theme='+document.documentElement.dataset.theme+(route==='westan-points-config'?'&config=1':'');}};
hub.activeSection=params.get('section')||'history';
if(params.get('receipt')==='1') {
 hub.activeSection='transfer';hub.transferStep='success';
 hub.reviewedTransfer={username:'Andreza',name:'Andreza',amount:20,description:'Obrigada pela ajuda!'};
 hub.transferMessage='20 pontos enviados para @Andreza.';
 hub.transferReceipt={id:3107,created_at:'2026-09-19T16:45:00Z'};
 hub.data.wallet.balance=978;
}
const nativeIf=Handlebars.helpers.if;
Handlebars.registerHelper('if',function(condition,...args){const opt=args.at(-1);return opt.fn?nativeIf.call(this,condition,opt):condition?args[0]:args[1];});
Handlebars.registerHelper('on',(event,handler)=>new Handlebars.SafeString('data-wp-on-'+event+'="'+handler.name+'"'));
Handlebars.registerHelper('didInsert',handler=>new Handlebars.SafeString('data-wp-insert="'+handler.name+'"'));
Handlebars.registerHelper('concat',(...args)=>args.slice(0,-1).join(''));
const icons=${JSON.stringify(icons)};
Handlebars.registerHelper('dIcon',name=>new Handlebars.SafeString('<svg class="d-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="'+(icons[name]||icons['circle-info'])+'"/></svg>'));
const template = Handlebars.template(${Handlebars.precompile(template)});
const root = document.querySelector('#preview');
let rendering = false;
function render() {
 rendering = true;
 const id=document.activeElement?.id;
 const start=document.activeElement?.selectionStart,end=document.activeElement?.selectionEnd;
 root.innerHTML=template(hub,{allowProtoPropertiesByDefault:true,allowProtoMethodsByDefault:true}).replace(/\\s(?:disabled|selected|required)=\"(?:false)?\"/g,'');
 root.querySelectorAll('[data-wp-insert]').forEach(element=>hub[element.dataset.wpInsert](element));
 if(id){const el=document.getElementById(id);el?.focus({preventScroll:true});if(start!=null)try{el?.setSelectionRange(start,end);}catch{}}
 rendering = false;
}
const originalSearch=hub.searchRecipients;
hub.searchRecipients=async value=>{await originalSearch.call(hub,value);render();};
for(const kind of ['click','input','change','submit','keydown','blur','mousedown','close']) {
 root.addEventListener(kind,event=>{
   if(rendering)return;
   const element=event.target.closest?.('[data-wp-on-'+kind+']');
   if(!element)return;
   const method=element.getAttribute('data-wp-on-'+kind);
   const result=hub[method]({target:event.target,currentTarget:element,key:event.key,clientX:event.clientX,clientY:event.clientY,preventDefault:()=>event.preventDefault()});
   if(kind==='mousedown'||kind==='blur'||(kind==='keydown'&&!event.defaultPrevented))return;
   render();
   if(result?.then)result.finally(render);
 },kind==='blur'||kind==='close');
}
document.querySelector('[data-demo-error]').addEventListener('click',event=>{failure=true;event.target.textContent='Falha de conexão preparada';});
render();
`;
fs.writeFileSync(path.join(out, 'preview.js'), script);
fs.writeFileSync(path.join(out, 'index.html'), `<!doctype html><html lang="pt-BR"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Westan Pontos — prévia dos ajustes</title><link rel="stylesheet" href="points.css"><style>:root{--primary:#18191d;--secondary:#fff}html[data-theme=dark]{--primary:#f1f2f5;--secondary:#121315}*{box-sizing:border-box}body{margin:0;background:var(--secondary);color:var(--primary);font:15px/1.5 system-ui,sans-serif}button,input,textarea,select{font:inherit}button{cursor:pointer}h1,h2,h3{line-height:1.2}.d-icon{width:1.1em;height:1.1em}.demo-bar{display:flex;gap:12px;flex-wrap:wrap;padding:10px 16px;border-bottom:1px solid #8883;font-size:12px}.demo-bar a,.demo-bar button{color:inherit}.demo-bar button{border:0;background:none;text-decoration:underline;font:inherit}.demo-bar span{opacity:.65}</style><body><nav class="demo-bar" aria-label="Controles de demonstração"><span>Prévia · nenhuma alteração no fórum</span><a href="?theme=light">Claro</a><a href="?theme=dark">Escuro</a><a href="?section=transfer">Transferir</a><a href="?config=1">Configurações</a><button data-demo-error>Simular falha na transferência</button></nav><div id="preview"></div><script src="handlebars.js"></script><script src="preview.js"></script></body></html>`);
console.log('GJS, Glimmer and Sass compiled. Interactive preview:', out);
