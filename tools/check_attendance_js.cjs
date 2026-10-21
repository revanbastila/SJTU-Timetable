const fs=require('fs'),vm=require('vm'),assert=require('assert');
const root=require('path').resolve(__dirname,'..');
const source=fs.readFileSync(root+'/lib/pages/attendance_web_page.dart','utf8');
const probe=source.match(/const attendanceVideoProbe = r'''([\s\S]*?)''';/)[1];
const kotlin=fs.readFileSync(root+'/android/app/src/main/kotlin/cn/sjtu/jiaotong_course/AttendanceFrameCapture.kt','utf8');
const lti=kotlin.match(/val code = """([\s\S]*?)"""\.trimIndent/)[1];
let count=0;
function test(name,fn){fn();count++;process.stdout.write('PASS '+name+'\n');}
const rect={left:100,top:50,right:900,bottom:500,width:800,height:450};
function node(text,extra={}){return {innerText:text,getBoundingClientRect:()=>rect,click(){this.clicked=(this.clicked||0)+1},...extra};}
function run({videos=[],buttons=[],frames=[]}={}){
 const context={window:{},innerWidth:1280,innerHeight:720,document:{querySelectorAll:q=>q==='video'?videos:q==='iframe'?frames:buttons}};
 return JSON.parse(vm.runInNewContext(probe,context));
}
test('video probe JS syntax',()=>new vm.Script(probe));
test('playing video returns bounded actual rectangle and clock',()=>{
 const result=run({videos:[node('',{paused:false,readyState:4,videoWidth:1920,videoHeight:1080,currentTime:6})]});
 assert.equal(result.playing,true);assert.equal(result.time,6);assert(result.x>=0&&result.x+result.width<=1);assert(result.y+result.height<=1);
});
test('empty player cannot claim a video frame',()=>assert.equal(run().playing,false));
test('unready video is not captured',()=>assert.equal(run({videos:[node('',{paused:false,readyState:0,videoWidth:0,videoHeight:0,play:()=>Promise.resolve()})]}).playing,false));
test('replay is never auto-selected',()=>{const replay=node('历史回放 直播中');run({buttons:[replay]});assert(!replay.clicked);});
test('only one explicit ongoing live entry can be selected',()=>{const live=node('直播中');run({buttons:[live]});assert.equal(live.clicked,1);});
test('multiple live entries require user selection',()=>{const one=node('直播中'),two=node('直播中');const r=run({buttons:[one,two]});assert(!one.clicked&&!two.clicked);assert(r.message.includes('多个'));});
test('live tab selection normalizes whitespace',()=>{const tab=node(' 直 播 ');run({buttons:[tab]});assert.equal(tab.clicked,1);});
test('only HTTPS player frames are followed',()=>{assert.equal(run({frames:[node('',{src:'http://player.example/video'})]}).frame,null);assert.equal(run({frames:[node('',{src:'https://player.example/video'})]}).frame,'https://player.example/video');});
test('LTI navigation script syntax',()=>new vm.Script(lti));
function formTest(path,action,isLti){
 class Form{submit(){this.submitted=true}requestSubmit(){this.submitted=true}}
 const context={URL,location:{href:'https://oc.sjtu.edu.cn'+path,pathname:path},HTMLFormElement:Form,document:{addEventListener(){}}};
 vm.runInNewContext(lti,context);
 const form=new Form();Object.assign(form,{target:'tool_content',action,querySelector:()=>isLti?{}:null,signedData:'fixture-signature'});form.submit();return form;
}
test('real LTI POST retains signed fields and changes window target',()=>{const f=formTest('/courses/91/external_tools/777','https://mlearning.sjtu.edu.cn/lti/launch',true);assert.equal(f.target,'_self');assert.equal(f.signedData,'fixture-signature');assert(f.submitted);});
test('non-LTI and login forms are untouched',()=>{assert.equal(formTest('/courses/91/external_tools/777','https://other.example/login',false).target,'tool_content');assert.equal(formTest('/login/canvas','https://mlearning.sjtu.edu.cn/lti/launch',true).target,'tool_content');});
test('insecure destinations are untouched',()=>assert.equal(formTest('/courses/91/external_tools/777','http://other.example/lti',true).target,'tool_content'));
console.log(count+' attendance JavaScript checks passed.');
