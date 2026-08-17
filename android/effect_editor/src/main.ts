import * as Blockly from 'blockly/core';
import 'blockly/blocks';
import * as zhHans from 'blockly/msg/zh-hans';
import * as ja from 'blockly/msg/ja';
import {FieldColour, registerFieldColour} from '@blockly/field-colour';
import {EFFECT_GEOMETRY} from './geometry';
import './style.css';

registerFieldColour();

type Bridge = {
  onWorkspaceChanged(json: string, blocks: number): void;
  onSaveRequested(json: string): void;
  onRunRequested(json: string): void;
  onHaptic(kind: string): void;
};

declare global {
  interface Window {
    MauryaBridge?: Bridge;
    MauryaEditor?: {
      load(json: string): void;
      save(): string;
      undo(): void;
      redo(): void;
      resize(): void;
      fit(): void;
      run(): void;
      editField(blockId: string, fieldName: string): void;
      insertWaitAfter(blockId: string, millis: number): boolean;
      setLanguage(language: string): void;
    };
  }
}

const params = new URLSearchParams(location.search);
const language = params.get('lang') === 'ja' ? 'ja' : 'zh';
Blockly.setLocale(language === 'ja' ? ja : zhHans);

const labels = language === 'ja' ? {
  start:'再生開始',light:'ライト',time:'時間',control:'制御',variables:'変数',math:'演算',logic:'条件',state:'状態',
  algorithms:'アルゴリズム',lists:'リスト',functions:'関数',sensors:'センサー',audio:'オーディオ',patterns:'パターン',
  all:`全${EFFECT_GEOMETRY.groupCount}グループ`,group:'グループ',set:'色を設定',fade:'色へ変化',hsv:'HSVを設定',adjust:'HSVを増減',
  mode:'点灯モード',wait:'待つ',repeat:'回繰り返す',forever:'ずっと繰り返す',end:'プログラム終了',
  steady:'常時点灯',strobe:'点滅',ms:'ミリ秒',sec:'秒',editNumber:'数値を編集',editColour:'色を編集',
  cancel:'キャンセル',confirm:'適用',fit:'全体表示',zoomIn:'拡大',zoomOut:'縮小',
  deleteBlock:'ブロックを削除',deleteNext:'削除するブロックをタップ',invalidHex:'#RRGGBB形式で入力してください',
  setVariable:'変数',to:'を',changeVariable:'数値変数',by:'増やす',numberVariable:'数値',
  booleanVariable:'真偽',colourVariable:'色',if:'もし',then:'なら',else:'それ以外',
  for:'繰り返す',from:'開始',through:'終了',step:'増分',while:'条件の間',break:'ループを抜ける',
  continue:'次の繰り返しへ',elapsed:'経過時間(ms)',lampState:'ライト状態',property:'値',
  colourLiteral:'色',colourFromHsv:'HSV色',min:'最小',max:'最大',clamp:'範囲内',
  allPixels:`全${EFFECT_GEOMETRY.pixelCount}ピクセル`,pixel:'ピクセル',pixelAt:'通し番号',pixelGroup:'グループ',
  applyPixelList:`色リストを${EFFECT_GEOMETRY.pixelCount}ピクセルへ繰り返し適用`,
} : {
  start:'开始播放',light:'灯光',time:'时间',control:'控制',variables:'变量',math:'运算',logic:'判断',state:'状态',
  algorithms:'算法',lists:'列表',functions:'函数',sensors:'传感器',audio:'音频',patterns:'图案',
  all:`全部${EFFECT_GEOMETRY.groupCount}组`,group:'第',set:'设置颜色',fade:'渐变到颜色',hsv:'设置HSV',adjust:'HSV增加/减少',
  mode:'灯光模式',wait:'等待',repeat:'次重复',forever:'永久重复',end:'结束程序',
  steady:'常亮',strobe:'频闪',ms:'毫秒',sec:'秒',editNumber:'修改数值',editColour:'修改颜色',
  cancel:'取消',confirm:'应用',fit:'显示全部',zoomIn:'放大',zoomOut:'缩小',
  deleteBlock:'删除积木',deleteNext:'点选要删除的积木',invalidHex:'请输入#RRGGBB格式',
  setVariable:'设置变量',to:'为',changeVariable:'数值变量',by:'增加',numberVariable:'数值',
  booleanVariable:'布尔',colourVariable:'颜色',if:'如果',then:'执行',else:'否则',
  for:'循环变量',from:'从',through:'到',step:'步长',while:'当条件成立',break:'跳出循环',
  continue:'继续下一轮',elapsed:'已运行时间(ms)',lampState:'灯组状态',property:'属性',
  colourLiteral:'颜色',colourFromHsv:'HSV颜色',min:'最小值',max:'最大值',clamp:'限制范围',
  allPixels:`全部${EFFECT_GEOMETRY.pixelCount}颗`,pixel:'灯珠',pixelAt:'全局编号',pixelGroup:'灯组',
  applyPixelList:`循环应用颜色列表到全部${EFFECT_GEOMETRY.pixelCount}颗`,
};

const targetOptions = [[labels.all,'ALL'], ...Array.from({length:EFFECT_GEOMETRY.groupCount},(_,i)=>[`${labels.group}${i+1}${language === 'zh' ? '组' : ''}`,`${i}`])] as [string,string][];
const groupOptions = Array.from({length:EFFECT_GEOMETRY.groupCount},(_,i)=>[`${labels.group}${i+1}${language === 'zh' ? '组' : ''}`,`${i}`]) as [string,string][];

const fieldEditor = document.querySelector<HTMLDivElement>('#field-editor')!;
const fieldEditorPanel = document.querySelector<HTMLElement>('.field-editor__panel')!;
const fieldTitle = document.querySelector<HTMLHeadingElement>('#field-editor-title')!;
const numberContent = document.querySelector<HTMLDivElement>('#field-editor-number')!;
const colourContent = document.querySelector<HTMLDivElement>('#field-editor-colour')!;
const numberRange = document.querySelector<HTMLInputElement>('#field-number-range')!;
const numberInput = document.querySelector<HTMLInputElement>('#field-number-input')!;
const colourSv = document.querySelector<HTMLDivElement>('#field-colour-sv')!;
const colourSvHandle = document.querySelector<HTMLSpanElement>('#field-colour-sv-handle')!;
const colourHue = document.querySelector<HTMLInputElement>('#field-colour-hue')!;
const colourH = document.querySelector<HTMLInputElement>('#field-colour-h')!;
const colourS = document.querySelector<HTMLInputElement>('#field-colour-s')!;
const colourV = document.querySelector<HTMLInputElement>('#field-colour-v')!;
const colourHex = document.querySelector<HTMLInputElement>('#field-colour-hex')!;
const colourBefore = document.querySelector<HTMLSpanElement>('#field-colour-before')!;
const colourAfter = document.querySelector<HTMLSpanElement>('#field-colour-after')!;
const colourError = document.querySelector<HTMLParagraphElement>('#field-colour-error')!;
const colourPresets = document.querySelector<HTMLDivElement>('#field-colour-presets')!;
const cancelButton = document.querySelector<HTMLButtonElement>('#field-editor-cancel')!;
const confirmButton = document.querySelector<HTMLButtonElement>('#field-editor-confirm')!;

cancelButton.textContent = labels.cancel;
confirmButton.textContent = labels.confirm;

let activeNumberField: Blockly.FieldNumber | null = null;
let activeColourField: FieldColour | null = null;
let colourState = {h:0,s:255,v:255};
let fieldEditorOpenPoint:{x:number;y:number}|null=null;

function visibleEditorContent() {
  return activeColourField ? colourContent : numberContent;
}

function updateVisualViewport() {
  const viewport=window.visualViewport;
  const layoutHeight=Math.max(1,window.innerHeight);
  const reportedHeight=viewport?.height;
  // Some Android System WebView builds transiently report a visual viewport
  // close to zero while a pointer gesture finishes. Using that value collapses
  // the field editor to a sub-pixel strip even though it is open. Trust the
  // visual viewport only when it is a plausible visible area; otherwise the
  // resized WebView layout viewport is the authoritative fallback.
  const hasPlausibleVisualHeight=
    typeof reportedHeight==='number'&&
    Number.isFinite(reportedHeight)&&
    reportedHeight>=120&&
    reportedHeight<=layoutHeight*1.1;
  const height=hasPlausibleVisualHeight
    ?Math.min(reportedHeight,layoutHeight)
    :layoutHeight;
  const reportedTop=hasPlausibleVisualHeight?(viewport?.offsetTop??0):0;
  const top=Math.max(0,Math.min(reportedTop,layoutHeight-height));
  document.documentElement.style.setProperty('--visual-viewport-height',`${height}px`);
  document.documentElement.style.setProperty('--visual-viewport-top',`${top}px`);
  if(!fieldEditor.hidden) {
    const focused=document.activeElement;
    if(focused instanceof HTMLElement && fieldEditor.contains(focused)) {
      requestAnimationFrame(()=>focused.scrollIntoView({block:'nearest',inline:'nearest'}));
    }
  }
  refreshWorkspaceLayout();
}

function prepareFieldEditor() {
  updateVisualViewport();
  const content=visibleEditorContent();
  content.scrollTop=0;
  fieldEditorPanel.scrollTop=0;
  requestAnimationFrame(()=>{
    content.scrollTop=0;
    updateVisualViewport();
  });
}

window.addEventListener('resize',updateVisualViewport);
window.addEventListener('orientationchange',updateVisualViewport);
window.visualViewport?.addEventListener('resize',updateVisualViewport);
window.visualViewport?.addEventListener('scroll',updateVisualViewport);

function normaliseHex(value:string) {
  const candidate = value.trim().toUpperCase();
  return /^#[0-9A-F]{6}$/.test(candidate) ? candidate : null;
}

function hsvToHex(h:number,s:number,v:number) {
  const sat = Math.max(0,Math.min(255,s))/255;
  const value = Math.max(0,Math.min(255,v))/255;
  const c = value*sat;
  const x = c*(1-Math.abs(((h/60)%2)-1));
  const m = value-c;
  const [r,g,b] = h<60?[c,x,0]:h<120?[x,c,0]:h<180?[0,c,x]:h<240?[0,x,c]:h<300?[x,0,c]:[c,0,x];
  return `#${[r,g,b].map(n=>Math.round((n+m)*255).toString(16).padStart(2,'0')).join('').toUpperCase()}`;
}

function hexToHsv(hex:string) {
  const value = normaliseHex(hex) ?? '#FFFFFF';
  const r=parseInt(value.slice(1,3),16)/255,g=parseInt(value.slice(3,5),16)/255,b=parseInt(value.slice(5,7),16)/255;
  const max=Math.max(r,g,b),min=Math.min(r,g,b),delta=max-min;
  let h=0;
  if(delta) {
    if(max===r) h=60*(((g-b)/delta)%6);
    else if(max===g) h=60*((b-r)/delta+2);
    else h=60*((r-g)/delta+4);
  }
  if(h<0) h+=360;
  return {h:Math.round(h)%360,s:Math.round(max===0?0:delta/max*255),v:Math.round(max*255)};
}

function renderColourState(updateHex=true) {
  colourState.h=((Math.round(colourState.h)%360)+360)%360;
  colourState.s=Math.max(0,Math.min(255,Math.round(colourState.s)));
  colourState.v=Math.max(0,Math.min(255,Math.round(colourState.v)));
  const hex=hsvToHex(colourState.h,colourState.s,colourState.v);
  colourHue.value=String(colourState.h);
  colourH.value=String(colourState.h);
  colourS.value=String(colourState.s);
  colourV.value=String(colourState.v);
  if(updateHex) colourHex.value=hex;
  colourAfter.style.backgroundColor=hex;
  colourSv.style.backgroundColor=hsvToHex(colourState.h,255,255);
  colourSvHandle.style.left=`${colourState.s/255*100}%`;
  colourSvHandle.style.top=`${(1-colourState.v/255)*100}%`;
  colourError.textContent='';
  confirmButton.disabled=false;
}

function closeFieldEditor() {
  fieldEditor.hidden=true;
  activeNumberField=null;
  activeColourField=null;
  fieldEditorOpenPoint=null;
  requestAnimationFrame(()=>requestAnimationFrame(refreshWorkspaceLayout));
}

cancelButton.addEventListener('click',closeFieldEditor);
fieldEditor.addEventListener('click',(event)=>{
  // Android dispatches a compatibility click at the original SVG coordinate
  // after pointerup. Once the modal is visible that same screen coordinate can
  // land on an HSV input or action button. Swallow only that opening click so
  // the editor never changes a value, focuses the keyboard, or closes itself.
  const point=normaliseEventPoint(event.clientX,event.clientY);
  if(
    performance.now()-lastFieldEditorOpenAt<500&&
    fieldEditorOpenPoint!==null&&
    Math.hypot(point.x-fieldEditorOpenPoint.x,point.y-fieldEditorOpenPoint.y)<24
  ) {
    event.preventDefault();
    event.stopImmediatePropagation();
  }
},true);
fieldEditor.querySelector('.field-editor__scrim')?.addEventListener('click',(event)=>{
  // Android synthesizes a click at the original field coordinate after
  // touchend. The modal now occupies that point, so without this guard the
  // just-opened editor immediately closes itself.
  if(performance.now()-lastFieldEditorOpenAt<500) {
    event.preventDefault();
    event.stopPropagation();
    return;
  }
  closeFieldEditor();
});
fieldEditor.addEventListener('pointerdown',(event)=>event.stopPropagation());
fieldEditor.addEventListener('keydown',(event)=>{
  if(event.key==='Escape') {
    event.preventDefault();
    event.stopPropagation();
    closeFieldEditor();
  } else if(event.key==='Enter' && event.target!==colourHex) {
    event.preventDefault();
    event.stopPropagation();
    confirmButton.click();
  }
});

confirmButton.addEventListener('click',()=>{
  if(activeNumberField) {
    const {inputMin:min,inputMax:max}=numberEditorBounds(activeNumberField);
    const next=Number(numberInput.value);
    if(!Number.isFinite(next)) return;
    activeNumberField.setValue(Math.max(min,Math.min(max,next)));
    (activeNumberField.getSourceBlock() as Blockly.BlockSvg | null)?.render();
  } else if(activeColourField) {
    const next=normaliseHex(colourHex.value);
    if(!next) {
      colourError.textContent=labels.invalidHex;
      confirmButton.disabled=true;
      return;
    }
    activeColourField.setValue(next);
    (activeColourField.getSourceBlock() as Blockly.BlockSvg | null)?.render();
  }
  closeFieldEditor();
});

type NumberEditorBounds={
  inputMin:number;
  inputMax:number;
  sliderMin:number;
  sliderMax:number;
  step:number;
};

function numberFieldContext(field:Blockly.FieldNumber) {
  const source=field.getSourceBlock() as Blockly.Block|null;
  if(!source) return {block:null,inputName:field.name??''};
  if(source.type!=='math_number') return {block:source,inputName:field.name??''};
  const parent=source.getParent();
  const input=parent?.inputList.find(item=>item.connection?.targetBlock()===source);
  return {block:parent??source,inputName:input?.name??field.name??''};
}

function numberEditorBounds(field:Blockly.FieldNumber):NumberEditorBounds {
  const value=Number(field.getValue());
  const fieldMin=Number.isFinite(field.getMin())?field.getMin():-1_000_000;
  const fieldMax=Number.isFinite(field.getMax())?field.getMax():1_000_000;
  const precision=field.getPrecision();
  const {block,inputName}=numberFieldContext(field);
  const type=block?.type??'';
  const functionName=String(block?.getFieldValue('FUNCTION')??'');
  const unit=String(block?.getFieldValue('UNIT')??'MS');

  const make=(inputMin:number,inputMax:number,sliderMin=inputMin,sliderMax=inputMax,step=1):NumberEditorBounds=>{
    const boundedInputMin=Math.max(fieldMin,inputMin);
    const boundedInputMax=Math.min(fieldMax,inputMax);
    return {
      inputMin:boundedInputMin,
      inputMax:boundedInputMax,
      sliderMin:Math.min(Math.max(boundedInputMin,sliderMin),value),
      sliderMax:Math.max(Math.min(boundedInputMax,sliderMax),value),
      step,
    };
  };

  if(inputName==='GROUP'&&type.startsWith('maurya_set_pixel_')) return make(1,7);
  if(inputName==='PIXEL'&&type.startsWith('maurya_set_pixel_')) return make(1,6);
  if(inputName==='INDEX'&&type.startsWith('maurya_set_pixel_at_')) return make(1,42);
  if(inputName==='INDEX'&&(type==='maurya_colour_list_get'||type==='maurya_number_list_get')) return make(0,41);
  if(inputName==='H'&&type.includes('hsv')) return make(type.includes('adjust')?-359:0,359);
  if((inputName==='S'||inputName==='V')&&type.includes('hsv')) return make(type.includes('adjust')?-255:0,255);
  if(inputName==='DURATION'&&(type.includes('wait')||type.includes('fade'))) {
    return unit==='SEC' ? make(0,600,0,60,1) : make(0,600_000,0,10_000,100);
  }
  if(inputName==='PARAM'&&type==='maurya_mode') return make(0,255);
  if(inputName==='COUNT'&&type==='maurya_repeat') return make(1,1000,1,100);
  if(inputName==='PERIOD'&&(type==='maurya_wave'||type==='maurya_square_wave')) return make(1,600_000,100,10_000,100);
  if(inputName==='DUTY'&&type==='maurya_square_wave') return make(0,1,0,1,.01);
  if(inputName==='PHASE'&&(type==='maurya_wave'||type==='maurya_square_wave')) return make(-1,1,-1,1,.01);
  if(inputName==='OCTAVES'&&type==='maurya_noise') return make(1,8);
  if(inputName==='PROGRESS'&&type==='maurya_pattern') return make(0,1,0,1,.01);
  if(inputName==='OFFSET'&&type==='maurya_pattern_list') return make(-42,42);
  if(inputName==='AMOUNT'&&type==='maurya_colour_mix') return make(0,1,0,1,.01);
  if(inputName==='AMOUNT'&&type==='maurya_colour_adjust') {
    return functionName==='ROTATE_HUE' ? make(-359,359) : make(-255,255);
  }
  if(type==='maurya_time_phase') {
    if(inputName==='A'&&functionName==='CYCLE') return make(1,600_000,100,10_000,100);
    if(inputName==='A') return make(20,300);
    if(inputName==='B'||inputName==='C') return make(1,16);
  }
  if(type==='maurya_algorithm_unary'&&['EASE_IN','EASE_OUT','EASE_IN_OUT'].includes(functionName)) return make(0,1,0,1,.01);
  if(type==='maurya_algorithm_binary'&&functionName==='DEADZONE'&&inputName==='B') return make(0,1,0,1,.01);

  const magnitude=Math.max(10,Math.abs(value));
  const sliderLimit=Math.min(1_000_000,Math.max(100,Math.ceil(magnitude*2)));
  const sliderMin=value<0?-sliderLimit:0;
  const step=precision>0?precision:(Number.isInteger(value)?1:.01);
  return make(fieldMin,fieldMax,sliderMin,sliderLimit,step);
}

function openNumberEditor(field:Blockly.FieldNumber) {
  activeNumberField=field;
  activeColourField=null;
  const {inputMin,inputMax,sliderMin,sliderMax,step}=numberEditorBounds(field);
  const value=Number(field.getValue());
  fieldTitle.textContent=labels.editNumber;
  numberContent.hidden=false;
  colourContent.hidden=true;
  Object.assign(numberRange,{min:String(sliderMin),max:String(sliderMax),step:String(step),value:String(value)});
  Object.assign(numberInput,{min:String(inputMin),max:String(inputMax),step:String(step),value:String(value)});
  numberRange.oninput=()=>{numberInput.value=numberRange.value;};
  numberInput.oninput=()=>{
    const next=Number(numberInput.value);
    if(Number.isFinite(next)) numberRange.value=String(Math.min(sliderMax,Math.max(sliderMin,next)));
  };
  lastFieldEditorOpenAt=performance.now();
  fieldEditor.hidden=false;
  prepareFieldEditor();
  requestAnimationFrame(()=>{numberInput.focus({preventScroll:true});numberInput.select();});
}

const presetColours=['#FF3B30','#FF9500','#FFCC00','#34C759','#39C5BB','#00A7FF','#006AFF','#5856D6','#AF52DE','#FF2D55','#FFFFFF','#808080','#111111'];

function setColourFromHex(value:string) {
  const next=normaliseHex(value);
  if(!next) {
    colourError.textContent=labels.invalidHex;
    confirmButton.disabled=true;
    return;
  }
  colourState=hexToHsv(next);
  renderColourState(false);
  colourHex.value=next;
}

function openColourEditor(field:FieldColour) {
  activeColourField=field;
  activeNumberField=null;
  const value=normaliseHex(String(field.getValue()))??'#FFFFFF';
  colourState=hexToHsv(value);
  fieldTitle.textContent=labels.editColour;
  numberContent.hidden=true;
  colourContent.hidden=false;
  colourBefore.style.backgroundColor=value;
  colourPresets.replaceChildren(...presetColours.map(colour=>{
    const button=document.createElement('button');
    button.type='button';
    button.className='colour-preset';
    button.style.backgroundColor=colour;
    button.setAttribute('aria-label',colour);
    button.onclick=()=>setColourFromHex(colour);
    return button;
  }));
  renderColourState();
  lastFieldEditorOpenAt=performance.now();
  fieldEditor.hidden=false;
  prepareFieldEditor();
}

colourHue.addEventListener('input',()=>{colourState.h=Number(colourHue.value);renderColourState();});
for(const input of [colourH,colourS,colourV]) {
  const update=()=>{
    const h=Number(colourH.value),s=Number(colourS.value),v=Number(colourV.value);
    if([h,s,v].every(Number.isFinite)) {
      colourState={h,s,v};
      renderColourState();
    }
  };
  input.addEventListener('input',update);
  input.addEventListener('change',update);
}
for(const eventName of ['input','change','blur']) colourHex.addEventListener(eventName,()=>setColourFromHex(colourHex.value));

function updateSv(event:PointerEvent) {
  const rect=colourSv.getBoundingClientRect();
  colourState.s=(Math.max(0,Math.min(rect.width,event.clientX-rect.left))/rect.width)*255;
  colourState.v=(1-Math.max(0,Math.min(rect.height,event.clientY-rect.top))/rect.height)*255;
  renderColourState();
}
colourSv.addEventListener('pointerdown',(event)=>{
  colourSv.setPointerCapture(event.pointerId);
  updateSv(event);
});
colourSv.addEventListener('pointermove',(event)=>{if(colourSv.hasPointerCapture(event.pointerId)) updateSv(event);});

class MobileNumberField extends Blockly.FieldNumber {
  protected override onMouseDown_(event:PointerEvent):void {
    if(event.pointerType==='touch'||event.pointerType==='pen'||navigator.maxTouchPoints>0){
      event.preventDefault();
      event.stopPropagation();
      fieldEditorOpenPoint=normaliseEventPoint(event.clientX,event.clientY);
      openNumberEditor(this);
      return;
    }
    super.onMouseDown_(event);
  }
  protected override showEditor_():void {openNumberEditor(this);}
  static override fromJson(options:Record<string,unknown>):MobileNumberField {
    return new MobileNumberField(options.value as number|undefined,options.min as number|undefined,options.max as number|undefined,options.precision as number|undefined);
  }
}
class MobileColourField extends FieldColour {
  protected override onMouseDown_(event:PointerEvent):void {
    if(event.pointerType==='touch'||event.pointerType==='pen'||navigator.maxTouchPoints>0){
      event.preventDefault();
      event.stopPropagation();
      fieldEditorOpenPoint=normaliseEventPoint(event.clientX,event.clientY);
      openColourEditor(this);
      return;
    }
    super.onMouseDown_(event);
  }
  protected override showEditor_():void {openColourEditor(this);}
  static override fromJson(options:Record<string,unknown>):MobileColourField {
    return new MobileColourField(options.colour as string|undefined);
  }
}
Blockly.fieldRegistry.register('field_mobile_number',MobileNumberField);
Blockly.fieldRegistry.register('field_mobile_colour',MobileColourField);

const numberField=(name:string,value:number,min=-1_000_000,max=1_000_000,precision=1)=>({type:'field_mobile_number',name,value,min,max,precision});
const numberInputArg=(name:string)=>({type:'input_value',name,check:'Number'});
const colourInputArg=(name:string)=>({type:'input_value',name,check:'Colour'});
const boolInputArg=(name:string)=>({type:'input_value',name,check:'Boolean'});
const numberListInputArg=(name:string)=>({type:'input_value',name,check:'NumberList'});
const colourListInputArg=(name:string)=>({type:'input_value',name,check:'ColourList'});
const variableField=(name:string,variable:string,type:string)=>({type:'field_variable',name,variable,variableTypes:[type],defaultType:type});

Blockly.defineBlocksWithJsonArray([
  {type:'maurya_start',message0:labels.start,nextStatement:null,colour:'#C8AA70',hat:'cap'},
  // Schema 1 blocks remain registered so saved programs load without data loss.
  {type:'maurya_set_color',message0:`${labels.set} %1 %2`,args0:[
    {type:'field_dropdown',name:'TARGET',options:targetOptions},{type:'field_mobile_colour',name:'COLOR',colour:'#FF3B6B'}],
    previousStatement:null,nextStatement:null,colour:'#7756D8'},
  {type:'maurya_fade',message0:`${labels.fade} %1 %2 ${labels.ms} %3`,args0:[
    {type:'field_dropdown',name:'TARGET',options:targetOptions},{type:'field_mobile_colour',name:'COLOR',colour:'#39C5BB'},
    numberField('DURATION',1000,100,600000,100)],previousStatement:null,nextStatement:null,colour:'#B14687'},
  {type:'maurya_set_hsv',message0:`${labels.hsv} %1 H %2 S %3 V %4`,args0:[
    {type:'field_dropdown',name:'TARGET',options:targetOptions},numberField('H',0,0,359),numberField('S',255,0,255),numberField('V',255,0,255)],
    previousStatement:null,nextStatement:null,colour:'#7047A8'},
  {type:'maurya_adjust_hsv',message0:`${labels.adjust} %1 ΔH %2 ΔS %3 ΔV %4`,args0:[
    {type:'field_dropdown',name:'TARGET',options:targetOptions},numberField('H',1,-359,359),numberField('S',0,-255,255),numberField('V',0,-255,255)],
    previousStatement:null,nextStatement:null,colour:'#7047A8'},
  {type:'maurya_wait',message0:`${labels.wait} %1 %2`,args0:[numberField('DURATION',1000,1,600000),
    {type:'field_dropdown',name:'UNIT',options:[[labels.ms,'MS'],[labels.sec,'SEC']]}],previousStatement:null,nextStatement:null,colour:'#258C92'},

  // Schema 2 expression-capable light and time blocks.
  {type:'maurya_set_color_value',message0:`${labels.set} %1 %2`,args0:[
    {type:'field_dropdown',name:'TARGET',options:targetOptions},colourInputArg('COLOR')],
    previousStatement:null,nextStatement:null,colour:'#7756D8'},
  {type:'maurya_fade_value',message0:`${labels.fade} %1 %2 ${labels.ms} %3`,args0:[
    {type:'field_dropdown',name:'TARGET',options:targetOptions},colourInputArg('COLOR'),numberInputArg('DURATION')],
    previousStatement:null,nextStatement:null,colour:'#B14687'},
  {type:'maurya_set_hsv_value',message0:`${labels.hsv} %1 H %2 S %3 V %4`,args0:[
    {type:'field_dropdown',name:'TARGET',options:targetOptions},numberInputArg('H'),numberInputArg('S'),numberInputArg('V')],
    previousStatement:null,nextStatement:null,colour:'#7047A8'},
  {type:'maurya_adjust_hsv_value',message0:`${labels.adjust} %1 ΔH %2 ΔS %3 ΔV %4`,args0:[
    {type:'field_dropdown',name:'TARGET',options:targetOptions},numberInputArg('H'),numberInputArg('S'),numberInputArg('V')],
    previousStatement:null,nextStatement:null,colour:'#7047A8'},
  {type:'maurya_wait_value',message0:`${labels.wait} %1 %2`,args0:[numberInputArg('DURATION'),
    {type:'field_dropdown',name:'UNIT',options:[[labels.ms,'MS'],[labels.sec,'SEC']]}],
    previousStatement:null,nextStatement:null,colour:'#258C92'},
  {type:'maurya_mode',message0:`${labels.mode} %1 %2 ${language==='ja'?'パラメータ':'参数'} %3`,args0:[
    {type:'field_dropdown',name:'TARGET',options:targetOptions},{type:'field_dropdown',name:'MODE',options:[[labels.steady,'1'],[labels.strobe,'3']]},
    numberField('PARAM',128,0,255)],previousStatement:null,nextStatement:null,colour:'#4369A8'},

  {type:'maurya_set_all_pixels_color_value',message0:`${labels.set} ${labels.allPixels} %1`,
    args0:[colourInputArg('COLOR')],previousStatement:null,nextStatement:null,colour:'#6C4FE0'},
  {type:'maurya_set_all_pixels_hsv_value',message0:`${labels.hsv} ${labels.allPixels} H %1 S %2 V %3`,
    args0:[numberInputArg('H'),numberInputArg('S'),numberInputArg('V')],
    previousStatement:null,nextStatement:null,colour:'#643FC2'},
  {type:'maurya_set_pixel_color_value',message0:`${labels.set} ${labels.pixelGroup} %1 ${labels.pixel} %2 %3`,
    args0:[numberInputArg('GROUP'),numberInputArg('PIXEL'),colourInputArg('COLOR')],
    previousStatement:null,nextStatement:null,colour:'#6C4FE0'},
  {type:'maurya_set_pixel_hsv_value',message0:`${labels.hsv} ${labels.pixelGroup} %1 ${labels.pixel} %2 H %3 S %4 V %5`,
    args0:[numberInputArg('GROUP'),numberInputArg('PIXEL'),numberInputArg('H'),numberInputArg('S'),numberInputArg('V')],
    previousStatement:null,nextStatement:null,colour:'#643FC2'},
  {type:'maurya_set_pixel_at_color_value',message0:`${labels.set} ${labels.pixelAt} %1 %2`,
    args0:[numberInputArg('INDEX'),colourInputArg('COLOR')],
    previousStatement:null,nextStatement:null,colour:'#6C4FE0'},
  {type:'maurya_set_pixel_at_hsv_value',message0:`${labels.hsv} ${labels.pixelAt} %1 H %2 S %3 V %4`,
    args0:[numberInputArg('INDEX'),numberInputArg('H'),numberInputArg('S'),numberInputArg('V')],
    previousStatement:null,nextStatement:null,colour:'#643FC2'},

  {type:'maurya_colour_literal',message0:`${labels.colourLiteral} %1`,args0:[{type:'field_mobile_colour',name:'COLOR',colour:'#39C5BB'}],output:'Colour',colour:'#7756D8'},
  {type:'maurya_hsv_colour',message0:`${labels.colourFromHsv} H %1 S %2 V %3`,args0:[numberInputArg('H'),numberInputArg('S'),numberInputArg('V')],output:'Colour',colour:'#7047A8'},

  {type:'maurya_var_set_number',message0:`${labels.setVariable} %1 ${labels.to} %2`,args0:[variableField('VAR',labels.numberVariable,'Number'),numberInputArg('VALUE')],previousStatement:null,nextStatement:null,colour:'#356ED1'},
  {type:'maurya_var_change_number',message0:`${labels.changeVariable} %1 ${labels.by} %2`,args0:[variableField('VAR',labels.numberVariable,'Number'),numberInputArg('VALUE')],previousStatement:null,nextStatement:null,colour:'#356ED1'},
  {type:'maurya_var_get_number',message0:'%1',args0:[variableField('VAR',labels.numberVariable,'Number')],output:'Number',colour:'#356ED1'},
  {type:'maurya_var_set_boolean',message0:`${labels.setVariable} %1 ${labels.to} %2`,args0:[variableField('VAR',labels.booleanVariable,'Boolean'),boolInputArg('VALUE')],previousStatement:null,nextStatement:null,colour:'#2F78C8'},
  {type:'maurya_var_get_boolean',message0:'%1',args0:[variableField('VAR',labels.booleanVariable,'Boolean')],output:'Boolean',colour:'#2F78C8'},
  {type:'maurya_var_set_colour',message0:`${labels.setVariable} %1 ${labels.to} %2`,args0:[variableField('VAR',labels.colourVariable,'Colour'),colourInputArg('VALUE')],previousStatement:null,nextStatement:null,colour:'#4864D8'},
  {type:'maurya_var_get_colour',message0:'%1',args0:[variableField('VAR',labels.colourVariable,'Colour')],output:'Colour',colour:'#4864D8'},

  {type:'maurya_minmax',message0:'%1 %2 %3',args0:[{type:'field_dropdown',name:'OP',options:[[labels.min,'MIN'],[labels.max,'MAX']]},numberInputArg('A'),numberInputArg('B')],output:'Number',colour:'#C25D75'},
  {type:'maurya_clamp',message0:`${labels.clamp} %1 ${labels.from} %2 ${labels.through} %3`,args0:[numberInputArg('VALUE'),numberInputArg('LOW'),numberInputArg('HIGH')],output:'Number',colour:'#C25D75'},

  {type:'maurya_if',message0:`${labels.if} %1`,args0:[boolInputArg('IF')],message1:`${labels.then} %1`,args1:[{type:'input_statement',name:'DO'}],previousStatement:null,nextStatement:null,colour:'#2E946B'},
  {type:'maurya_if_else',message0:`${labels.if} %1`,args0:[boolInputArg('IF')],message1:`${labels.then} %1`,args1:[{type:'input_statement',name:'DO'}],message2:`${labels.else} %1`,args2:[{type:'input_statement',name:'ELSE'}],previousStatement:null,nextStatement:null,colour:'#2E946B'},
  {type:'maurya_repeat',message0:`%1 ${labels.repeat}`,args0:[numberField('COUNT',3,1,1000)],message1:'%1',args1:[{type:'input_statement',name:'DO'}],previousStatement:null,nextStatement:null,colour:'#B87928'},
  {type:'maurya_forever',message0:labels.forever,message1:'%1',args1:[{type:'input_statement',name:'DO'}],previousStatement:null,nextStatement:null,colour:'#B87928'},
  {type:'maurya_for',message0:`${labels.for} %1 ${labels.from} %2 ${labels.through} %3 ${labels.step} %4`,args0:[
    variableField('VAR','i','Number'),numberInputArg('FROM'),numberInputArg('TO'),numberInputArg('BY')],
    message1:`${labels.then} %1`,args1:[{type:'input_statement',name:'DO'}],previousStatement:null,nextStatement:null,colour:'#B87928'},
  {type:'maurya_while',message0:`${labels.while} %1`,args0:[boolInputArg('IF')],message1:`${labels.then} %1`,args1:[{type:'input_statement',name:'DO'}],previousStatement:null,nextStatement:null,colour:'#B87928'},
  {type:'maurya_break',message0:labels.break,previousStatement:null,nextStatement:null,colour:'#C45C3E'},
  {type:'maurya_continue',message0:labels.continue,previousStatement:null,nextStatement:null,colour:'#C45C3E'},
  {type:'maurya_end',message0:labels.end,previousStatement:null,colour:'#C8AA70'},

  {type:'maurya_elapsed',message0:labels.elapsed,output:'Number',colour:'#A653B5'},
  {type:'maurya_group_value',message0:`${labels.lampState} %1 ${labels.property} %2`,args0:[
    {type:'field_dropdown',name:'GROUP',options:groupOptions},{type:'field_dropdown',name:'PROPERTY',options:[['Hue','H'],['Saturation','S'],['Value','V'],[labels.mode,'MODE']]}],
    output:'Number',colour:'#A653B5'},

  {type:'maurya_algorithm_unary',message0:'%1 %2',args0:[
    {type:'field_dropdown',name:'FUNCTION',options:[['abs','ABS'],['round','ROUND'],['floor','FLOOR'],['ceil','CEIL'],['sqrt','SQRT'],['log','LOG'],['sin','SIN'],['cos','COS'],['deg→rad','RADIANS'],['rad→deg','DEGREES'],['ease in','EASE_IN'],['ease out','EASE_OUT'],['ease in-out','EASE_IN_OUT']]},
    numberInputArg('A')],output:'Number',colour:'#D25A82'},
  {type:'maurya_algorithm_binary',message0:'%1 %2 %3',args0:[
    {type:'field_dropdown',name:'FUNCTION',options:[['pow','POWER'],['deadzone','DEADZONE']]},
    numberInputArg('A'),numberInputArg('B')],output:'Number',colour:'#D25A82'},
  {type:'maurya_algorithm_ternary',message0:'%1 %2 %3 %4',args0:[
    {type:'field_dropdown',name:'FUNCTION',options:[['lerp','LERP'],['smoothstep','SMOOTHSTEP'],['smootherstep','SMOOTHERSTEP']]},
    numberInputArg('A'),numberInputArg('B'),numberInputArg('C')],output:'Number',colour:'#D25A82'},
  {type:'maurya_wave',message0:'%1 period %2 phase %3',args0:[
    {type:'field_dropdown',name:'FUNCTION',options:[['sin wave','SINE_WAVE'],['triangle','TRIANGLE_WAVE'],['saw','SAW_WAVE']]},
    numberInputArg('PERIOD'),numberInputArg('PHASE')],output:'Number',colour:'#B14A86'},
  {type:'maurya_square_wave',message0:'square period %1 duty %2 phase %3',args0:[
    numberInputArg('PERIOD'),numberInputArg('DUTY'),numberInputArg('PHASE')],output:'Number',colour:'#B14A86'},
  {type:'maurya_noise',message0:'%1 x %2 seed %3 octaves %4',args0:[
    {type:'field_dropdown',name:'FUNCTION',options:[['noise 1D','NOISE_1D'],['fBm noise','FBM_NOISE']]},
    numberInputArg('X'),numberInputArg('SEED'),numberInputArg('OCTAVES')],output:'Number',colour:'#8A58B8'},
  {type:'maurya_random_number',message0:'random %1 to %2',args0:[
    numberInputArg('LOW'),numberInputArg('HIGH')],output:'Number',colour:'#D25A82'},
  {type:'maurya_random_colour',message0:'random visible colour',output:'Colour',colour:'#8D5CD6'},
  {type:'maurya_seed_random',message0:'seed random %1',args0:[
    numberInputArg('SEED')],previousStatement:null,nextStatement:null,colour:'#D25A82'},
  {type:'maurya_colour_unary',message0:'%1 %2',args0:[
    {type:'field_dropdown',name:'FUNCTION',options:[['complement','COMPLEMENT']]},colourInputArg('COLOUR')],
    output:'Colour',colour:'#8D5CD6'},
  {type:'maurya_colour_adjust',message0:'%1 %2 amount %3',args0:[
    {type:'field_dropdown',name:'FUNCTION',options:[['rotate hue','ROTATE_HUE'],['saturation','ADJUST_SATURATION'],['brightness','ADJUST_VALUE']]},
    colourInputArg('COLOUR'),numberInputArg('AMOUNT')],output:'Colour',colour:'#8D5CD6'},
  {type:'maurya_colour_mix',message0:'%1 %2 %3 amount %4',args0:[
    {type:'field_dropdown',name:'FUNCTION',options:[['mix RGB','MIX_RGB'],['mix HSV','MIX_HSV']]},
    colourInputArg('A'),colourInputArg('B'),numberInputArg('AMOUNT')],output:'Colour',colour:'#8D5CD6'},
  {type:'maurya_runtime_number',message0:'%1',args0:[{type:'field_dropdown',name:'KEY',options:[
    ['accel X','SENSOR_ACCEL_X'],['accel Y','SENSOR_ACCEL_Y'],['accel Z','SENSOR_ACCEL_Z'],
    ['motion','SENSOR_MOTION'],['shake','SENSOR_SHAKE'],['gyro X','SENSOR_GYRO_X'],['gyro Y','SENSOR_GYRO_Y'],
    ['gyro Z','SENSOR_GYRO_Z'],['pitch','SENSOR_PITCH'],['roll','SENSOR_ROLL'],['yaw','SENSOR_YAW'],
    ['light','SENSOR_LIGHT'],['near','SENSOR_NEAR'],['heading','SENSOR_HEADING'],['pressure','SENSOR_PRESSURE']]}],
    output:'Number',colour:'#2F9D81'},
  {type:'maurya_audio_number',message0:'%1',args0:[{type:'field_dropdown',name:'KEY',options:[
    ['audio level','AUDIO_LEVEL'],['audio peak','AUDIO_PEAK'],['bass','AUDIO_BASS'],['mid','AUDIO_MID'],
    ['treble','AUDIO_TREBLE'],['BPM','AUDIO_BPM']]}],output:'Number',colour:'#DD6A4F'},
  {type:'maurya_audio_beat',message0:'audio beat',output:'Boolean',colour:'#DD6A4F'},
  {type:'maurya_time_phase',message0:'%1 A %2 B %3 C %4',args0:[
    {type:'field_dropdown',name:'FUNCTION',options:[['cycle','CYCLE'],['beat phase','BEAT_PHASE'],['bar phase','BAR_PHASE']]},
    numberInputArg('A'),numberInputArg('B'),numberInputArg('C')],output:'Number',colour:'#258C92'},
  {type:'maurya_colour_list7',message0:'7 colours %1 %2 %3 %4 %5 %6 %7',args0:[
    colourInputArg('C1'),colourInputArg('C2'),colourInputArg('C3'),colourInputArg('C4'),
    colourInputArg('C5'),colourInputArg('C6'),colourInputArg('C7')],output:'ColourList',colour:'#3C79C9'},
  {type:'maurya_number_list7',message0:'7 numbers %1 %2 %3 %4 %5 %6 %7',args0:[
    numberInputArg('N1'),numberInputArg('N2'),numberInputArg('N3'),numberInputArg('N4'),
    numberInputArg('N5'),numberInputArg('N6'),numberInputArg('N7')],output:'NumberList',colour:'#3C79C9'},
  {type:'maurya_colour_list_get',message0:'colour list %1 index %2',args0:[
    colourListInputArg('LIST'),numberInputArg('INDEX')],output:'Colour',colour:'#3C79C9'},
  {type:'maurya_number_list_get',message0:'number list %1 index %2',args0:[
    numberListInputArg('LIST'),numberInputArg('INDEX')],output:'Number',colour:'#3C79C9'},
  {type:'maurya_list_length',message0:'list length %1',args0:[
    {type:'input_value',name:'LIST',check:['NumberList','ColourList']}],output:'Number',colour:'#3C79C9'},
  {type:'maurya_apply_colour_list',message0:language==='ja'?'7色を全グループへ適用 %1':'应用7色到全部灯组 %1',
    args0:[colourListInputArg('LIST')],previousStatement:null,nextStatement:null,colour:'#3C79C9'},
  {type:'maurya_apply_pixel_colour_list',message0:`${labels.applyPixelList} %1`,
    args0:[colourListInputArg('LIST')],previousStatement:null,nextStatement:null,colour:'#315FC0'},
  {type:'maurya_pattern',message0:'%1 progress %2',args0:[
    {type:'field_dropdown',name:'FUNCTION',options:[['chase','CHASE'],['wave','WAVE_PATTERN']]},
    numberInputArg('PROGRESS')],output:'NumberList',colour:'#5270C9'},
  {type:'maurya_pattern_list',message0:'%1 list %2 offset %3',args0:[
    {type:'field_dropdown',name:'FUNCTION',options:[['mirror','MIRROR'],['rotate','ROTATE_PATTERN'],['center spread','CENTER_SPREAD'],['center contract','CENTER_CONTRACT']]},
    {type:'input_value',name:'LIST',check:['NumberList','ColourList']},numberInputArg('OFFSET')],
    output:null,colour:'#5270C9'},
  {type:'maurya_function_def',message0:language==='ja'?'手続き関数 %1 を定義':'定义流程函数 %1',
    args0:[{type:'field_input',name:'NAME',text:language==='ja'?'点滅':'闪烁'}],
    message1:language==='ja'?'処理 %1':'执行 %1',args1:[{type:'input_statement',name:'BODY'}],
    colour:'#7B5AB5',tooltip:language==='ja'?'引数のない再利用可能な処理を定義します。型付き引数と戻り値はコードモードで利用できます。':'定义可复用的无参数流程；带类型参数和返回值请使用代码模式。'},
  {type:'maurya_function_call',message0:language==='ja'?'手続き関数 %1 を呼ぶ':'调用流程函数 %1',
    args0:[{type:'field_input',name:'NAME',text:language==='ja'?'点滅':'闪烁'}],
    previousStatement:null,nextStatement:null,colour:'#7B5AB5'},
]);

const shadowNumber=(value:number)=>({shadow:{type:'math_number',fields:{NUM:value}}});
const shadowBoolean=(value:boolean)=>({shadow:{type:'logic_boolean',fields:{BOOL:value?'TRUE':'FALSE'}}});
const shadowColour=(value:string)=>({shadow:{type:'maurya_colour_literal',fields:{COLOR:value}}});
const block=(type:string,inputs:Record<string,unknown>={})=>({kind:'block',type,...(Object.keys(inputs).length?{inputs}:{})});

const toolbox = {
  kind:'categoryToolbox',
  contents:[
    {kind:'category',name:labels.light,colour:'#7756D8',contents:[
      block('maurya_start'),block('maurya_set_color_value',{COLOR:shadowColour('#FF3B30')}),
      block('maurya_fade_value',{COLOR:shadowColour('#39C5BB'),DURATION:shadowNumber(1000)}),
      block('maurya_set_hsv_value',{H:shadowNumber(0),S:shadowNumber(255),V:shadowNumber(255)}),
      block('maurya_adjust_hsv_value',{H:shadowNumber(1),S:shadowNumber(0),V:shadowNumber(0)}),block('maurya_mode'),
      block('maurya_set_all_pixels_color_value',{COLOR:shadowColour('#39C5BB')}),
      block('maurya_set_all_pixels_hsv_value',{H:shadowNumber(0),S:shadowNumber(255),V:shadowNumber(255)}),
      block('maurya_set_pixel_color_value',{GROUP:shadowNumber(1),PIXEL:shadowNumber(1),COLOR:shadowColour('#FF2D55')}),
      block('maurya_set_pixel_hsv_value',{GROUP:shadowNumber(1),PIXEL:shadowNumber(1),H:shadowNumber(0),S:shadowNumber(255),V:shadowNumber(255)}),
      block('maurya_set_pixel_at_color_value',{INDEX:shadowNumber(1),COLOR:shadowColour('#1677FF')}),
      block('maurya_set_pixel_at_hsv_value',{INDEX:shadowNumber(1),H:shadowNumber(210),S:shadowNumber(255),V:shadowNumber(255)}),
      block('maurya_colour_literal'),block('maurya_hsv_colour',{H:shadowNumber(0),S:shadowNumber(255),V:shadowNumber(255)})]},
    {kind:'category',name:labels.time,colour:'#258C92',contents:[
      block('maurya_wait_value',{DURATION:shadowNumber(1000)}),block('maurya_elapsed')]},
    {kind:'category',name:labels.variables,colour:'#356ED1',contents:[
      block('maurya_var_set_number',{VALUE:shadowNumber(0)}),block('maurya_var_change_number',{VALUE:shadowNumber(1)}),block('maurya_var_get_number'),
      block('maurya_var_set_boolean',{VALUE:shadowBoolean(true)}),block('maurya_var_get_boolean'),
      block('maurya_var_set_colour',{VALUE:shadowColour('#39C5BB')}),block('maurya_var_get_colour')]},
    {kind:'category',name:labels.math,colour:'#C25D75',contents:[
      block('math_number'),block('math_arithmetic',{A:shadowNumber(1),B:shadowNumber(1)}),block('math_modulo',{DIVIDEND:shadowNumber(10),DIVISOR:shadowNumber(3)}),
      block('maurya_minmax',{A:shadowNumber(0),B:shadowNumber(255)}),block('maurya_clamp',{VALUE:shadowNumber(128),LOW:shadowNumber(0),HIGH:shadowNumber(255)})]},
    {kind:'category',name:labels.logic,colour:'#2E946B',contents:[
      block('logic_boolean'),block('logic_compare',{A:shadowNumber(0),B:shadowNumber(0)}),block('logic_operation',{A:shadowBoolean(true),B:shadowBoolean(false)}),
      block('logic_negate',{BOOL:shadowBoolean(true)}),block('maurya_if',{IF:shadowBoolean(true)}),block('maurya_if_else',{IF:shadowBoolean(true)})]},
    {kind:'category',name:labels.control,colour:'#B87928',contents:[
      block('maurya_repeat'),block('maurya_forever'),block('maurya_for',{FROM:shadowNumber(0),TO:shadowNumber(359),BY:shadowNumber(5)}),
      block('maurya_while',{IF:shadowBoolean(true)}),block('maurya_break'),block('maurya_continue'),block('maurya_end')]},
    {kind:'category',name:labels.state,colour:'#A653B5',contents:[block('maurya_group_value'),block('maurya_elapsed')]},
    {kind:'category',name:labels.algorithms,colour:'#D25A82',contents:[
      block('maurya_algorithm_unary',{A:shadowNumber(0.5)}),block('maurya_algorithm_binary',{A:shadowNumber(2),B:shadowNumber(3)}),
      block('maurya_algorithm_ternary',{A:shadowNumber(0),B:shadowNumber(1),C:shadowNumber(0.5)}),
      block('maurya_wave',{PERIOD:shadowNumber(2000),PHASE:shadowNumber(0)}),
      block('maurya_square_wave',{PERIOD:shadowNumber(1000),DUTY:shadowNumber(0.5),PHASE:shadowNumber(0)}),
      block('maurya_noise',{X:shadowNumber(0),SEED:shadowNumber(1),OCTAVES:shadowNumber(3)}),
      block('maurya_random_number',{LOW:shadowNumber(0),HIGH:shadowNumber(1)}),
      block('maurya_random_colour'),block('maurya_seed_random',{SEED:shadowNumber(1)}),
      block('maurya_colour_unary',{COLOUR:shadowColour('#39C5BB')}),
      block('maurya_colour_adjust',{COLOUR:shadowColour('#39C5BB'),AMOUNT:shadowNumber(30)}),
      block('maurya_colour_mix',{A:shadowColour('#FF2D55'),B:shadowColour('#1677FF'),AMOUNT:shadowNumber(0.5)})]},
    {kind:'category',name:labels.lists,colour:'#3C79C9',contents:[
      block('maurya_colour_list7',{C1:shadowColour('#FF2D55'),C2:shadowColour('#FF9500'),C3:shadowColour('#FFD60A'),
        C4:shadowColour('#39FF88'),C5:shadowColour('#39C5BB'),C6:shadowColour('#1677FF'),C7:shadowColour('#AF52DE')}),
      block('maurya_number_list7',{N1:shadowNumber(0),N2:shadowNumber(1),N3:shadowNumber(2),N4:shadowNumber(3),N5:shadowNumber(4),N6:shadowNumber(5),N7:shadowNumber(6)}),
      block('maurya_colour_list_get',{INDEX:shadowNumber(0)}),block('maurya_number_list_get',{INDEX:shadowNumber(0)}),
      block('maurya_list_length'),block('maurya_apply_colour_list'),block('maurya_apply_pixel_colour_list')]},
    {kind:'category',name:labels.sensors,colour:'#2F9D81',contents:[block('maurya_runtime_number')]},
    {kind:'category',name:labels.audio,colour:'#DD6A4F',contents:[block('maurya_audio_number'),block('maurya_audio_beat')]},
    {kind:'category',name:labels.patterns,colour:'#5270C9',contents:[
      block('maurya_pattern',{PROGRESS:shadowNumber(0)}),block('maurya_pattern_list',{OFFSET:shadowNumber(1)}),
      block('maurya_time_phase',{A:shadowNumber(2000),B:shadowNumber(4),C:shadowNumber(4)})]},
    {kind:'category',name:labels.functions,colour:'#7B5AB5',contents:[
      block('maurya_function_def'),block('maurya_function_call')]},
  ],
};

const theme=Blockly.Theme.defineTheme('maurya',{
  base:Blockly.Themes.Zelos,
  blockStyles:{
    math_blocks:{colourPrimary:'#C25D75'},
    logic_blocks:{colourPrimary:'#2E946B'},
    variable_blocks:{colourPrimary:'#356ED1'},
    variable_dynamic_blocks:{colourPrimary:'#356ED1'},
  },
  componentStyles:{
    workspaceBackgroundColour:'#070912',toolboxBackgroundColour:'#10131E',toolboxForegroundColour:'#F5F6FF',
    flyoutBackgroundColour:'#171B29',flyoutForegroundColour:'#F5F6FF',flyoutOpacity:0.98,
    scrollbarColour:'#586083',scrollbarOpacity:0.65,insertionMarkerColour:'#B8C5FF',
    insertionMarkerOpacity:0.8,cursorColour:'#C8AA70',
  },
  fontStyle:{family:'sans-serif',weight:'600',size:13},
});

(Blockly.Scrollbar as unknown as {scrollbarThickness:number}).scrollbarThickness=10;
Blockly.config.dragRadius=8;
Blockly.config.snapRadius=42;
Blockly.config.connectingSnapRadius=42;

const workspace=Blockly.inject('editor',{
  toolbox,theme,renderer:'zelos',media:'./media/',trashcan:false,
  move:{scrollbars:true,drag:true,wheel:true},
  zoom:{controls:false,wheel:true,startScale:0.7,maxScale:1.4,minScale:0.35,scaleSpeed:1.1,pinch:true},
  grid:{spacing:24,length:2,colour:'#29304F',snap:true},maxUndo:50,sounds:false,
});

type WorkspacePanState={
  pointerId:number;
  startX:number;
  startY:number;
  scrollX:number;
  scrollY:number;
  moved:boolean;
};
let workspacePan:WorkspacePanState|null=null;
const workspaceSvg=workspace.getParentSvg();

function isBlankWorkspaceTarget(target:EventTarget|null) {
  if(!(target instanceof Element)) return false;
  return !target.closest(
    '.blocklyDraggable,.blocklyFlyout,.blocklyToolboxDiv,'+
    '.blocklyScrollbarVertical,.blocklyScrollbarHorizontal,'+
    '.blocklyWidgetDiv,.blocklyDropDownDiv,#workspace-controls',
  );
}

// Blockly's built-in canvas drag is unreliable in some Android System WebView
// releases. Own only gestures that start on empty workspace; block dragging,
// fields, flyouts and scrollbars continue to use Blockly unchanged.
workspaceSvg.addEventListener('pointerdown',(event)=>{
  if(event.button!==0||!isBlankWorkspaceTarget(event.target)||!fieldEditor.hidden) return;
  workspacePan={
    pointerId:event.pointerId,
    startX:event.clientX,
    startY:event.clientY,
    scrollX:workspace.scrollX,
    scrollY:workspace.scrollY,
    moved:false,
  };
  workspaceSvg.setPointerCapture(event.pointerId);
  event.preventDefault();
  event.stopImmediatePropagation();
},true);
workspaceSvg.addEventListener('pointermove',(event)=>{
  const pan=workspacePan;
  if(!pan||pan.pointerId!==event.pointerId) return;
  const dx=event.clientX-pan.startX;
  const dy=event.clientY-pan.startY;
  if(!pan.moved&&Math.hypot(dx,dy)<4) return;
  pan.moved=true;
  workspace.scroll(pan.scrollX+dx,pan.scrollY+dy);
  event.preventDefault();
  event.stopImmediatePropagation();
},true);
function finishWorkspacePan(event:PointerEvent) {
  const pan=workspacePan;
  if(!pan||pan.pointerId!==event.pointerId) return;
  workspacePan=null;
  if(workspaceSvg.hasPointerCapture(event.pointerId)) {
    workspaceSvg.releasePointerCapture(event.pointerId);
  }
  if(pan.moved) {
    event.preventDefault();
    event.stopImmediatePropagation();
  }
}
workspaceSvg.addEventListener('pointerup',finishWorkspacePan,true);
workspaceSvg.addEventListener('pointercancel',finishWorkspacePan,true);

function refreshWorkspaceLayout() {
  Blockly.svgResize(workspace);
  workspace.resizeContents();
}

type FieldGestureStart={x:number;y:number;time:number;pointerId:number|string};
type EditableField={
  field:Blockly.Field;
  kind:'number'|'colour';
};
type PendingFieldGesture=FieldGestureStart&{
  field:EditableField;
  timer:number;
};
let fieldPointerStart:PendingFieldGesture|null=null;
let fieldNativeTouchStart:PendingFieldGesture|null=null;
let lastFieldEditorOpenAt=0;
function normaliseEventPoint(x:number,y:number) {
  // Several Android System WebView builds expose MotionEvent coordinates in
  // physical pixels while SVG geometry is reported in CSS pixels.
  if(x>window.innerWidth+1||y>window.innerHeight+1) {
    return {x:x/window.devicePixelRatio,y:y/window.devicePixelRatio};
  }
  return {x,y};
}
function editableFieldKind(field:Blockly.Field,root:SVGElement):EditableField['kind']|null {
  const value=field.getValue();
  const name=(field as Blockly.Field&{name?:string}).name;
  // The SVG class attached to custom fields differs between Blockly's normal
  // browser renderer and some Android System WebView builds. Prefer the actual
  // field type/name/value and keep the rendered class only as a final fallback.
  if(
    field instanceof MobileColourField||
    field instanceof FieldColour||
    name==='COLOR'||
    (typeof value==='string'&&/^#[0-9A-F]{6}$/i.test(value))||
    root.classList.contains('blocklyColourField')
  ) return 'colour';
  if(
    field instanceof MobileNumberField||
    field instanceof Blockly.FieldNumber||
    typeof value==='number'||
    root.classList.contains('blocklyNumberField')
  ) return 'number';
  return null;
}
function editableFieldFromTarget(target:EventTarget|null):EditableField|null {
  if(!(target instanceof Element)) return null;
  for(const blockItem of workspace.getAllBlocks(false)) {
    for(const field of blockItem.getFields()) {
      const root=field.getSvgRoot();
      if(!root||!(root===target||root.contains(target))) continue;
      const kind=editableFieldKind(field,root);
      if(kind) return {field,kind};
    }
  }
  return null;
}
function editableFieldAt(x:number,y:number,target:EventTarget|null=null):EditableField|null {
  const targeted=editableFieldFromTarget(target);
  if(targeted) return targeted;
  for(const blockItem of workspace.getAllBlocks(false)) {
    for(const field of blockItem.getFields()) {
      const root=field.getSvgRoot();
      if(!root) continue;
      const kind=editableFieldKind(field,root);
      if(!kind) continue;
      const rect=root.getBoundingClientRect();
      if(x>=rect.left-6&&x<=rect.right+6&&y>=rect.top-6&&y<=rect.bottom+6) return {field,kind};
    }
  }
  return null;
}
function openEditableField(field:EditableField,point?:{x:number;y:number}) {
  if(!fieldEditor.hidden) return false;
  fieldEditorOpenPoint=point??null;
  if(field.kind==='number') openNumberEditor(field.field as Blockly.FieldNumber);
  else openColourEditor(field.field as FieldColour);
  lastFieldEditorOpenAt=performance.now();
  return true;
}
function tryOpenEditableFieldAt(x:number,y:number) {
  const field=editableFieldAt(x,y);
  return field?openEditableField(field,{x,y}):false;
}
function beginFieldGesture(
  x:number,
  y:number,
  pointerId:number|string,
  target:EventTarget|null,
  assign:(value:PendingFieldGesture|null)=>void,
) {
  const field=editableFieldAt(x,y,target);
  if(!field) {
    assign(null);
    return;
  }
  // A timer is required for Android WebViews where Blockly retains pointer
  // capture and neither pointerup nor the synthetic click reaches window.
  const pending={} as PendingFieldGesture;
  Object.assign(pending,{x,y,time:performance.now(),pointerId,field});
  pending.timer=window.setTimeout(()=>{
    openEditableField(field,{x,y});
    assign(null);
  },260);
  assign(pending);
}
function moveFieldGesture(start:PendingFieldGesture|null,x:number,y:number,clear:()=>void) {
  if(start&&Math.hypot(x-start.x,y-start.y)>=8) {
    clearTimeout(start.timer);
    clear();
  }
}
function endFieldGesture(start:PendingFieldGesture|null,x:number,y:number,pointerId:number|string) {
  if(!start||start.pointerId!==pointerId) return false;
  clearTimeout(start.timer);
  if(performance.now()-start.time>350||Math.hypot(x-start.x,y-start.y)>=8) return false;
  return openEditableField(start.field,{x:start.x,y:start.y});
}
window.addEventListener('pointerdown',(event)=>{
  const point=normaliseEventPoint(event.clientX,event.clientY);
  beginFieldGesture(point.x,point.y,event.pointerId,event.target,(value)=>{fieldPointerStart=value;});
},true);
window.addEventListener('pointermove',(event)=>{
  const point=normaliseEventPoint(event.clientX,event.clientY);
  moveFieldGesture(fieldPointerStart,point.x,point.y,()=>{fieldPointerStart=null;});
},true);
window.addEventListener('pointerup',(event)=>{
  const start=fieldPointerStart;
  fieldPointerStart=null;
  const point=normaliseEventPoint(event.clientX,event.clientY);
  if(endFieldGesture(start,point.x,point.y,event.pointerId)) {
    event.preventDefault();
    event.stopImmediatePropagation();
  }
},true);
// Android WebView/Blockly can retain pointer capture until after pointerup. Native
// touch events remain observable in the capture phase, so use them as the mobile
// fallback without placing an element over the Blockly field (which would break
// dragging and connection snapping).
document.addEventListener('touchstart',(event)=>{
  if(event.touches.length!==1) {
    if(fieldNativeTouchStart) clearTimeout(fieldNativeTouchStart.timer);
    fieldNativeTouchStart=null;
    return;
  }
  const touch=event.touches[0];
  const point=normaliseEventPoint(touch.clientX,touch.clientY);
  beginFieldGesture(point.x,point.y,touch.identifier,event.target,(value)=>{fieldNativeTouchStart=value;});
},{capture:true,passive:true});
document.addEventListener('touchmove',(event)=>{
  if(event.touches.length!==1) return;
  const touch=event.touches[0];
  const point=normaliseEventPoint(touch.clientX,touch.clientY);
  moveFieldGesture(fieldNativeTouchStart,point.x,point.y,()=>{fieldNativeTouchStart=null;});
},{capture:true,passive:true});
document.addEventListener('touchend',(event)=>{
  const start=fieldNativeTouchStart;
  fieldNativeTouchStart=null;
  if(!start||event.changedTouches.length!==1) return;
  const touch=event.changedTouches[0];
  const point=normaliseEventPoint(touch.clientX,touch.clientY);
  if(endFieldGesture(start,point.x,point.y,touch.identifier)) {
    event.preventDefault();
    event.stopImmediatePropagation();
  }
},{capture:true,passive:false});
// Some OEM WebViews synthesize click but omit pointerup after Blockly has taken
// capture. This final fallback is intentionally read-only until a field hit is
// confirmed, and is de-duplicated from the pointer/touch paths.
document.addEventListener('click',(event)=>{
  if(performance.now()-lastFieldEditorOpenAt<400) return;
  const point=normaliseEventPoint(event.clientX,event.clientY);
  if(tryOpenEditableFieldAt(point.x,point.y)) {
    event.preventDefault();
    event.stopImmediatePropagation();
  }
},true);

const controls={
  fit:document.querySelector<HTMLButtonElement>('#control-fit')!,
  zoomIn:document.querySelector<HTMLButtonElement>('#control-zoom-in')!,
  zoomOut:document.querySelector<HTMLButtonElement>('#control-zoom-out')!,
  deleteBlock:document.querySelector<HTMLButtonElement>('#control-delete')!,
};
controls.fit.title=labels.fit;
controls.zoomIn.title=labels.zoomIn;
controls.zoomOut.title=labels.zoomOut;
controls.deleteBlock.title=labels.deleteBlock;
controls.fit.onclick=()=>workspace.zoomToFit();
controls.zoomIn.onclick=()=>workspace.zoomCenter(1);
controls.zoomOut.onclick=()=>workspace.zoomCenter(-1);

let deleteMode=false;
function selectedBlock():Blockly.BlockSvg|null {
  const selected=Blockly.common.getSelected();
  if(selected instanceof Blockly.BlockSvg) return selected;
  if(selected instanceof Blockly.Field) return selected.getSourceBlock() as Blockly.BlockSvg|null;
  return null;
}
function setDeleteMode(enabled:boolean) {
  deleteMode=enabled;
  controls.deleteBlock.classList.toggle('is-active',enabled);
  controls.deleteBlock.title=enabled?labels.deleteNext:labels.deleteBlock;
}
function deleteNow(blockItem:Blockly.BlockSvg) {
  if(!blockItem.isDeletable()) return;
  setDeleteMode(false);
  blockItem.dispose(true);
  window.MauryaBridge?.onHaptic('delete');
}
controls.deleteBlock.onclick=()=>{
  const selected=selectedBlock();
  if(selected) deleteNow(selected); else setDeleteMode(!deleteMode);
};
workspaceSvg.addEventListener('pointerdown',(event)=>{
  if(!deleteMode) return;
  const element=event.target as Element;
  if(!element.closest('.blocklyDraggable')) setDeleteMode(false);
});

let changeTimer=0;
workspace.addChangeListener((event)=>{
  if(deleteMode&&event.type===Blockly.Events.SELECTED) {
    const selectedId=(event as Blockly.Events.Selected).newElementId;
    const selected=selectedId?workspace.getBlockById(selectedId):null;
    if(selected instanceof Blockly.BlockSvg) {
      requestAnimationFrame(()=>deleteNow(selected));
      return;
    }
  }
  if(event.type===Blockly.Events.BLOCK_MOVE||event.type===Blockly.Events.BLOCK_CREATE||event.type===Blockly.Events.BLOCK_DELETE) {
    window.MauryaBridge?.onHaptic('tick');
  }
  clearTimeout(changeTimer);
  changeTimer=window.setTimeout(()=>{
    const json=JSON.stringify(Blockly.serialization.workspaces.save(workspace));
    window.MauryaBridge?.onWorkspaceChanged(json,workspace.getAllBlocks(false).length);
  },120);
});

window.MauryaEditor={
  load(json:string) {
    workspace.clear();
    if(json) Blockly.serialization.workspaces.load(JSON.parse(json),workspace);
    requestAnimationFrame(()=>requestAnimationFrame(()=>{refreshWorkspaceLayout();workspace.zoomToFit();}));
  },
  save(){return JSON.stringify(Blockly.serialization.workspaces.save(workspace));},
  undo(){workspace.undo(false);},
  redo(){workspace.undo(true);},
  resize(){refreshWorkspaceLayout();},
  fit(){refreshWorkspaceLayout();workspace.zoomToFit();},
  run(){window.MauryaBridge?.onRunRequested(this.save());},
  editField(blockId:string,fieldName:string) {
    const field=workspace.getBlockById(blockId)?.getField(fieldName) as (Blockly.Field&{showEditor_?:()=>void})|null;
    field?.showEditor_?.();
  },
  insertWaitAfter(blockId:string,millis:number) {
    const source=workspace.getBlockById(blockId);
    if(!source?.nextConnection) return false;
    Blockly.Events.setGroup(true);
    try {
      const oldTarget=source.nextConnection.targetConnection;
      if(oldTarget) source.nextConnection.disconnect();
      const wait=workspace.newBlock('maurya_wait') as Blockly.BlockSvg;
      wait.initSvg();
      const useSeconds=millis%1000===0;
      wait.setFieldValue(useSeconds?String(millis/1000):String(millis),'DURATION');
      wait.setFieldValue(useSeconds?'SEC':'MS','UNIT');
      wait.render();
      source.nextConnection.connect(wait.previousConnection);
      if(oldTarget&&wait.nextConnection) wait.nextConnection.connect(oldTarget);
      wait.select();
      window.MauryaBridge?.onHaptic('tick');
      requestAnimationFrame(()=>{refreshWorkspaceLayout();workspace.centerOnBlock(wait.id);});
      return true;
    } finally {
      Blockly.Events.setGroup(false);
    }
  },
  setLanguage(){},
};
addEventListener('resize',()=>requestAnimationFrame(refreshWorkspaceLayout));
