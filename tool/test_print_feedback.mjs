import vm from 'node:vm';
import fs from 'node:fs';
import assert from 'node:assert/strict';
const source=fs.readFileSync('build/print-feedback.js','utf8');
function fixture(origin='https://fixture.example') {
 const messages=[];const timers=new Map();let click;let sequence=0;let changed;
 const window={PortalPrintState:{postMessage:v=>messages.push(v)}};window.top=window;
 const document={addEventListener:(name,fn,capture)=>{assert.equal(name,'click');assert.equal(capture,true);click=fn;}};
 vm.runInNewContext(source,{window,location:{origin},document,MutationObserver:class { constructor(fn){changed=fn;} observe(){} },setTimeout:fn=>{timers.set(++sequence,fn);return sequence;},clearTimeout:id=>timers.delete(id)});
 function tap(text='طباعة',isTrusted=true,title='',id='') {
  const button={id,textContent:text,title,disabled:false,getAttribute:()=>null};
  const event={isTrusted,target:{closest:()=>button},prevented:false,stopped:false,
   preventDefault(){this.prevented=true;},stopImmediatePropagation(){this.stopped=true;}};
  click(event);return event;
 }
 return {window,messages,timers,tap,change:node=>changed([{target:node}]),get click(){return click;}};
}
const f=fixture();
assert.equal(f.tap().prevented,false);assert.deepEqual(f.messages,['start']);
const repeat=f.tap();assert.equal(repeat.prevented,true);assert.equal(repeat.stopped,true);assert.equal(f.messages.length,1);
assert.equal(f.tap('طباعة',false).prevented,false);
f.window.__portalFinishPrint();assert.equal(f.timers.size,0);
assert.equal(f.tap('إغلاق المعاينة').prevented,false);
f.tap('معاينة / طباعة PDF',true,'','layoutPreview');assert.equal(f.messages.length,1);
f.tap('🖨',true,'طباعة الفاتورة');assert.equal(f.messages.length,2);
[...f.timers.values()][0]();assert.equal(f.messages.at(-1),'finish');
assert.equal(fixture('https://other.example').click,undefined);
const validation=fixture();validation.tap();
validation.change({nodeType:1,closest:()=>({id:'message',textContent:'أضف مادة للفاتورة قبل الطباعة.'})});
assert.equal(validation.messages.at(-1),'finish');
assert.equal(validation.tap().prevented,false);
const save=fixture();save.tap();
save.change({nodeType:1,closest:()=>({id:'designStatus',textContent:'تم حفظ التصميم واعتماده للطباعة'})});
assert.deepEqual(save.messages,['start']);
save.change({nodeType:1,closest:()=>({id:'designStatus',textContent:'تعذر حفظ التصميم'})});
assert.equal(save.messages.at(-1),'finish');
console.log('Print feedback: first tap, duplicate blocking, synthetic click, cleanup, timeout, icon label and origin checks passed.');
