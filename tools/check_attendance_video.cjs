// Node + jsdom, development only. NODE_PATH can point to a separate harness.
const fs=require('fs'),vm=require('vm'),assert=require('assert');
const {JSDOM}=require('jsdom');
const root=require('path').resolve(__dirname,'..');
const source=fs.readFileSync(root+'/lib/services/attendance_video_probe.dart','utf8');
const probe=source.match(/const attendanceVideoProbe = r'''([\s\S]*?)''';/)[1];
const manual=source.match(/const attendanceUseCurrentView = r'''([\s\S]*?)''';/)[1];
const kotlin=fs.readFileSync(root+'/android/app/src/main/kotlin/cn/sjtu/jiaotong_course/AttendanceFrameCapture.kt','utf8');
const lti=kotlin.match(/val code = """([\s\S]*?)"""\.trimIndent/)[1];
let count=0;
function test(name,fn){fn();count++;console.log('PASS '+name);}
// Sanitized observed SJTU DOM. Click handlers update rendered selection labels.
const layout=`<div class="video-layout-control-popper">
 <button class="video-layout-segment__item">单屏</button><button class="video-layout-segment__item active">双屏</button>
 <div class="video-layout-select-row"><div class="video-layout-select-row__label">主屏幕展示</div>
 <div class="el-select__placeholder">教师1</div><li role="option" class="is-selected">教师1</li>
 <li role="option" class="is-disabled" aria-disabled="true">PPT</li></div>
 <div class="video-layout-select-row"><div class="video-layout-select-row__label">副屏幕展示</div><div class="el-select__placeholder">PPT</div></div>
 <button class="video-layout-switch-btn">一键切换主副视角</button><div title="画面布局" class="control-btn"></div></div>`;
function fixture({hasLayout=true,selectedPpt=false,single=false,swapWorks=true,singleWorks=true}={}){
 const dom=new JSDOM(`<div id="playerModule">${hasLayout?layout:''}<div class="jkp-stage-layout__primary"><video id="main"></video></div>
 <div class="player-layout-secondary"><video id="camera"></video></div><div class="jkp-hover-wrap"></div>
 <div id="pptHorizontalWrapper"><button>收起</button></div></div>`,{runScripts:'outside-only',url:'https://v.sjtu.edu.cn/'});
 const w=dom.window,d=w.document;let now=1000;w.Date.now=()=>now;
 Object.defineProperty(w,'innerWidth',{value:1000});Object.defineProperty(w,'innerHeight',{value:800});
 const rect=(left,top,width,height)=>({left,top,width,height,right:left+width,bottom:top+height});
 w.Element.prototype.getBoundingClientRect=function(){return this._rect||rect(0,0,160,40);};
 const hits={swap:0,single:0,collapse:0,leave:0};
 function media(id,bounds){const v=d.getElementById(id);v._rect=bounds;
  for(const [key,value] of Object.entries({paused:false,readyState:4,videoWidth:1920,videoHeight:1080,currentTime:2,currentSrc:'https://media.invalid/fresh'}))
   Object.defineProperty(v,key,{value,writable:true,configurable:true});v.play=()=>Promise.resolve();return v;}
 const main=media('main',rect(0,90,800,450)),camera=media('camera',rect(800,90,200,112));
 const labels=d.querySelectorAll('.el-select__placeholder'),singles=d.querySelectorAll('.video-layout-segment__item');
 if(hasLayout){
  if(selectedPpt){labels[0].textContent='PPT';labels[1].textContent='教师1';}
  if(single){singles[0].classList.add('active');singles[1].classList.remove('active');}
  d.querySelector('.video-layout-switch-btn').onclick=()=>{hits.swap++;if(swapWorks){
   const p=labels[0].textContent;labels[0].textContent=labels[1].textContent;labels[1].textContent=p;main.currentTime=0;main.currentSrc='https://media.invalid/ppt';}};
  singles[0].onclick=()=>{hits.single++;if(singleWorks){singles[0].classList.add('active');singles[1].classList.remove('active');camera.style.display='none';main._rect=rect(0,90,1000,562.5);}};
 }
 d.querySelector('#pptHorizontalWrapper button').onclick=()=>{hits.collapse++;d.querySelector('#pptHorizontalWrapper').style.display='none';};
 d.querySelector('.jkp-hover-wrap').addEventListener('mouseleave',()=>hits.leave++);
 const run=()=>JSON.parse(w.eval(probe));
 const tick=(ms=1000)=>{now+=ms;main.currentTime++;camera.currentTime++;return run();};
 const finish=()=>{let r;for(let i=0;i<16;i++)r=tick();return r;};
 return{w,d,main,camera,hits,run,tick,finish,advance:ms=>now+=ms,manual:()=>w.eval(manual)};
}
test('all injected scripts parse',()=>[probe,manual,lti].forEach(s=>new vm.Script(s)));
test('dual view swaps PPT to main then confirms single view and hides overlays',()=>{
 const f=fixture();assert(!f.run().playing);assert.equal(f.hits.swap,1);assert(!f.tick().playing);assert.equal(f.hits.single,1);
 assert(!f.tick().playing);const r=f.tick();assert(r.playing);assert.equal(r.viewState,'ready');assert.equal(r.width,1);
 assert.equal(f.hits.collapse,1);assert.equal(f.hits.leave,1);f.finish();assert.equal(f.hits.swap,1);assert.equal(f.hits.single,1);
});
test('already selected PPT and single view never toggle away',()=>{
 const f=fixture({selectedPpt:true,single:true});f.run();assert(f.tick().playing);assert.equal(f.hits.swap,0);assert.equal(f.hits.single,0);
});
test('unassigned PPT uses enabled actual main-view option',()=>{
 const f=fixture(),rows=f.d.querySelectorAll('.video-layout-select-row');rows[1].querySelector('.el-select__placeholder').textContent='教师2';
 const option=rows[0].querySelectorAll('[role=option]')[1];option.classList.remove('is-disabled');option.removeAttribute('aria-disabled');
 let clicks=0;option.onclick=()=>{clicks++;rows[0].querySelector('.el-select__placeholder').textContent='PPT';};
 f.finish();assert.equal(clicks,1);assert.equal(f.hits.swap,0);assert.equal(f.run().viewState,'ready');
});
test('delayed PPT controls are discovered',()=>{
 const f=fixture(),l=f.d.querySelector('.video-layout-control-popper');l.remove();assert(!f.run().playing);f.advance(5000);
 f.d.getElementById('playerModule').prepend(l);f.finish();assert.equal(f.hits.swap,1);assert.equal(f.run().viewState,'ready');
});
test('missing controls fall back after bounded wait with a reason',()=>{
 const f=fixture({hasLayout:false});assert(!f.run().playing);const r=f.finish();assert(r.playing);assert.equal(r.viewState,'fallback');assert(r.message.includes('未找到'));
});
test('failed swap falls back without retrying or claiming PPT',()=>{
 const f=fixture({swapWorks:false});f.run();const r=f.finish();assert(r.playing);assert.equal(r.viewState,'fallback');assert(r.message.includes('未成功'));assert.equal(f.hits.swap,1);
});
test('failed single-view switch falls back without retrying',()=>{
 const f=fixture({singleWorks:false});f.finish();assert.equal(f.run().viewState,'fallback');assert.equal(f.hits.single,1);
});
test('manual override cancels pending selection and repeated override stays sampleable',()=>{
 const f=fixture();f.run();f.manual();const r=f.tick();assert(r.playing);assert.equal(r.viewState,'manual');f.manual();assert.equal(f.tick().frameKey,r.frameKey);assert.equal(f.hits.single,0);
});
test('manual before first probe prevents automatic selection',()=>{
 const f=fixture();f.manual();assert.equal(f.tick().viewState,'manual');assert.equal(f.hits.swap,0);
});
test('trusted user interaction cancels automation',()=>{
 const f=fixture(),handlers=[],original=f.d.addEventListener.bind(f.d);
 f.d.addEventListener=(name,fn,...rest)=>{if(name==='pointerdown')handlers.push(fn);original(name,fn,...rest);};
 f.run();handlers[0]({isTrusted:true,target:f.d.querySelector('[title="画面布局"]')});assert.equal(f.tick().viewState,'manual');assert.equal(f.hits.single,0);
});
test('buffering main PPT never captures a playing camera thumbnail',()=>{
 const f=fixture({selectedPpt:true,single:true});f.main.readyState=0;f.finish();assert(!f.run().playing);
});
test('stream and crop changes replace opaque frame identity',()=>{
 const f=fixture({selectedPpt:true,single:true});f.run();const a=f.tick();f.main.currentSrc='https://media.invalid/new';const b=f.tick();assert.notEqual(a.frameKey,b.frameKey);assert(!b.frameKey.includes('https'));
 f.main._rect={left:0,top:90,width:700,height:400,right:700,bottom:490};assert.notEqual(b.frameKey,f.tick().frameKey);
});
test('offscreen and hidden videos cannot produce frames',()=>{
 const f=fixture({hasLayout:false});f.main._rect={left:0,top:900,right:800,bottom:1350,width:800,height:450};f.camera.style.display='none';f.finish();assert(!f.run().playing);
});
test('PPT thumbnails and audio menu cannot select the view',()=>{
 const f=fixture({hasLayout:false});f.d.body.insertAdjacentHTML('beforeend','<div class="control-popper"><li>PPT</li><span>声道</span></div><button>PPT</button>');
 let clicked=0;f.d.querySelector('li').onclick=()=>clicked++;f.finish();assert.equal(clicked,0);assert.equal(f.run().viewState,'fallback');
});
test('playing recording is rejected while actual live tab is selected',()=>{
 const f=fixture({selectedPpt:true,single:true});f.d.body.insertAdjacentHTML('afterbegin','<div class="tab-item active">点播</div><div class="tab-item">直播</div>');let clicked=0;
 f.d.querySelectorAll('.tab-item')[1].onclick=()=>clicked++;assert(!f.run().playing);assert.equal(clicked,1);assert(!f.tick().playing);assert.equal(clicked,1);
});
function mobileFixture({dual=true,alreadyPpt=false,applyWorks=true,hasPpt=true}={}){
 const f=fixture({hasLayout:false}),d=f.d,module=d.getElementById('playerModule');
 const mobile=d.createElement('div');mobile.className='live-detail-mobile';module.replaceWith(mobile);mobile.append(module);
 module.querySelector('.jkp-stage-layout__primary').className='mobile-primary-player';
 mobile.insertAdjacentHTML('beforeend',`<div class="portrait-wrapper"><div class="controller-wrapper"><div class="left">
 <div role="switch" aria-checked="${dual}"></div><span>${dual?'双':'单'}视角播放</span></div>
 <button>视角</button><button>声道</button></div></div>
 <div class="select-channel-sheet" style="display:none"><div class="van-cell ${alreadyPpt?'':'active'}"><div class="van-cell__title">教师1</div></div>
 ${hasPpt?`<div class="van-cell ${alreadyPpt?'active':''}"><div class="van-cell__title">PPT</div></div>`:''}
 <button>确定</button><button class="van-action-sheet__cancel">取消</button></div>`);
 const toggle=mobile.querySelector('[role=switch]'),sheet=mobile.querySelector('.select-channel-sheet'),cells=[...sheet.querySelectorAll('.van-cell')];
 toggle.onclick=()=>{toggle.setAttribute('aria-checked','false');toggle.nextElementSibling.textContent='单视角播放';f.camera.style.display='none';};
 mobile.querySelector('.controller-wrapper button').onclick=()=>sheet.style.display='block';
 cells.forEach(cell=>cell.onclick=()=>{cells.forEach(c=>c.classList.remove('active'));cell.classList.add('active');});
 sheet.querySelector('button').onclick=()=>{sheet.style.display='none';if(applyWorks){f.main.currentSrc='https://media.invalid/ppt-mobile';f.main.currentTime=0;}};
 sheet.querySelector('.van-action-sheet__cancel').onclick=()=>sheet.style.display='none';
 return {...f,sheet,toggle};
}
test('actual mobile controls select single then PPT and confirm the changed live stream',()=>{
 const f=mobileFixture();const r=f.finish();assert(r.playing);assert.equal(r.viewState,'ready');assert.equal(f.toggle.getAttribute('aria-checked'),'false');assert.equal(f.sheet.style.display,'none');
});
test('mobile already-selected PPT is confirmed without changing to camera',()=>{
 const f=mobileFixture({dual:false,alreadyPpt:true,applyWorks:false});const r=f.finish();assert(r.playing);assert.equal(r.viewState,'ready');
});
test('mobile confirm without changing the old camera stream cannot claim PPT',()=>{
 const f=mobileFixture({applyWorks:false});const r=f.finish();assert(r.playing);assert.equal(r.viewState,'fallback');
});
test('mobile missing PPT option closes selector before fallback',()=>{
 const f=mobileFixture({hasPpt:false});f.finish();f.tick();assert.equal(f.run().viewState,'fallback');assert.equal(f.sheet.style.display,'none');
});
test('mobile main buffering does not capture its secondary camera',()=>{
 const f=mobileFixture();f.main.readyState=0;f.finish();assert(!f.run().playing);
});
test('mobile manual selection leaves native view controls to the user',()=>{
 const f=mobileFixture();f.manual();assert.equal(f.finish().viewState,'manual');assert.equal(f.toggle.getAttribute('aria-checked'),'true');
});
test('LTI POST retains signed fields and changes only the form target',()=>{
 class Form{submit(){this.submitted=true}requestSubmit(){this.submitted=true}}
 const context={URL,location:{href:'https://oc.sjtu.edu.cn/courses/91/external_tools/777',pathname:'/courses/91/external_tools/777'},HTMLFormElement:Form,document:{addEventListener(){}}};
 vm.runInNewContext(lti,context);const f=new Form();Object.assign(f,{target:'tool_content',action:'https://mlearning.sjtu.edu.cn/lti/launch',querySelector:()=>({}),signedData:'fixture'});
 f.submit();assert.equal(f.target,'_self');assert.equal(f.signedData,'fixture');assert(f.submitted);
});
test('not-started player waits past two minutes then discovers late PPT controls',()=>{
 const f=fixture(),module=f.d.getElementById('playerModule');module.remove();
 f.d.body.innerHTML='<div class="no-permission">直播未开始</div>';
 assert.equal(f.run().liveState,'notStarted');f.advance(181000);
 assert.equal(f.run().liveState,'notStarted');assert.equal(f.hits.swap,0);
 f.d.body.replaceChildren(module);f.finish();
 const r=f.run();assert(r.playing);assert.equal(r.viewState,'ready');
 assert.equal(f.hits.swap,1);assert.equal(f.hits.single,1);
});
test('late video after generic empty state restarts discovery budget',()=>{
 const f=fixture(),module=f.d.getElementById('playerModule');module.remove();
 f.finish();f.advance(180000);f.d.body.append(module);f.finish();
 assert.equal(f.run().viewState,'ready');assert.equal(f.hits.swap,1);
});
test('manual override while waiting survives delayed live startup',()=>{
 const f=fixture(),module=f.d.getElementById('playerModule');module.remove();
 f.d.body.innerHTML='<div class="no-permission">直播未开始</div>';
 f.run();f.manual();f.advance(181000);f.d.body.replaceChildren(module);f.finish();
 assert.equal(f.run().viewState,'manual');assert.equal(f.hits.swap,0);assert.equal(f.hits.single,0);
});
test('course-list not-started labels never suppress a playing live',()=>{
 const f=fixture({selectedPpt:true,single:true});
 f.d.body.insertAdjacentHTML('beforeend','<button>另一节课直播未开始</button>');f.finish();
 assert(f.run().playing);assert.notEqual(f.run().liveState,'notStarted');
});
console.log(count+' attendance JavaScript checks passed.');
