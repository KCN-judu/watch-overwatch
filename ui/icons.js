'use strict';
// Lucide 0.468.0 is bundled locally; see ui/vendor/LICENSE.
const ICON_NAMES={user:'UserRound',swords:'Swords',chart:'ChartNoAxesCombined',history:'History',library:'BookOpen',activity:'Activity',settings:'Settings',sun:'Sun'};
function icon(name,label=''){
  const node=lucide.createElement(lucide.icons[ICON_NAMES[name]]||lucide.icons.Activity,{'class':'ui-icon','aria-hidden':label?'false':'true','stroke-width':'1.8'});
  if(label){node.setAttribute('role','img');node.setAttribute('aria-label',label);}
  return node.outerHTML;
}
function hydrateIcons(){document.querySelectorAll('[data-icon]').forEach(el=>{if(!el.querySelector('.ui-icon'))el.insertAdjacentHTML('afterbegin',icon(el.dataset.icon,el.dataset.label||''));});}
document.addEventListener('DOMContentLoaded',hydrateIcons);
