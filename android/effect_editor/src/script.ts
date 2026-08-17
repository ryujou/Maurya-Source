import {EditorState} from '@codemirror/state';
import {EditorView,keymap,lineNumbers,highlightActiveLine,highlightActiveLineGutter} from '@codemirror/view';
import {defaultKeymap,history,historyKeymap,indentWithTab,undo as cmUndo,redo as cmRedo} from '@codemirror/commands';
import {cpp} from '@codemirror/lang-cpp';
import {autocompletion,completionKeymap,CompletionContext} from '@codemirror/autocomplete';
import {bracketMatching,syntaxHighlighting,HighlightStyle,indentUnit} from '@codemirror/language';
import {searchKeymap,highlightSelectionMatches} from '@codemirror/search';
import {lintGutter,setDiagnostics,Diagnostic} from '@codemirror/lint';
import {tags} from '@lezer/highlight';
import './script.css';

declare global {
  interface Window {
    MauryaBridge?: {
      onSourceChanged(source:string,lines:number):void;
      onRunRequested(source:string):void;
      onHaptic(kind:string):void;
    };
    MauryaScriptEditor: {
      load(source:string):void;
      save():string;
      undo():void;
      redo():void;
      run():void;
      format():void;
      insertWaitAfter(offset:number,millis:number):void;
      showDiagnostic(start:number,end:number,message:string):void;
      clearDiagnostics():void;
      focusRange(start:number,end:number):void;
    };
  }
}

const params=new URLSearchParams(location.search);
const japanese=params.get('lang')==='ja';
const keywords=[
  'effect','fn','return','let','number','bool','color','target','if','else','repeat','forever','for','from','to','step',
  'while','break','continue','end','wait','all','group','hsv','min','max','clamp',
  'pow','abs','round','floor','ceil','sqrt','log','sin','cos','radians','degrees','map',
  'lerp','smoothstep','smootherstep','easeIn','easeOut','easeInOut','sineWave','triangleWave',
  'sawWave','squareWave','random','randomColor','seedRandom','noise1D','fbmNoise','smooth',
  'deadzone','hysteresis','peakHold','debounce','risingEdge','fallingEdge','rgb','mixRgb',
  'mixHsv','complement','rotateHue','adjustSaturation','adjustValue','paletteColor','mirror',
  'rotatePattern','centerSpread','centerContract','chase','wavePattern','sensor','audio','time',
  'true','false','STEADY','STROBE','elapsedMs','accelX','accelY','accelZ','motion','shake',
  'gyroX','gyroY','gyroZ','pitch','roll','yaw','light','near','heading','pressure','level',
  'peak','bass','mid','treble','beat','bpm','cycle','beatPhase','barPhase',
];
const methods=['color','hsv','adjustHsv','fade','mode','hue','saturation','value'];
const completions=[...keywords,...methods].map(label=>({
  label,
  type:keywords.includes(label)?'keyword':'method',
  info:japanese?'Maurya Script の予約語':'Maurya Script关键字',
}));
function complete(context:CompletionContext){
  const word=context.matchBefore(/[A-Za-z_][A-Za-z0-9_]*/);
  if(!word&&!context.explicit)return null;
  return {from:word?.from??context.pos,options:completions};
}

const theme=EditorView.theme({
  '&':{height:'100%',backgroundColor:'#070912',color:'#F5F6FF',fontSize:'16px'},
  '.cm-content':{fontFamily:'ui-monospace, SFMono-Regular, Consolas, monospace',padding:'18px 4px',caretColor:'#B8C5FF'},
  '.cm-line':{padding:'0 12px'},
  '.cm-gutters':{backgroundColor:'#10131E',color:'#737B9D',border:'none'},
  '.cm-activeLine,.cm-activeLineGutter':{backgroundColor:'#171B29'},
  '.cm-selectionBackground,.cm-content ::selection':{backgroundColor:'#39446F !important'},
  '.cm-cursor':{borderLeftColor:'#C8AA70'},
  '.cm-tooltip':{backgroundColor:'#171B29',color:'#F5F6FF',border:'1px solid #39405C'},
  '.cm-tooltip-autocomplete ul li[aria-selected]':{backgroundColor:'#303A62',color:'#FFFFFF'},
  '.cm-lintRange-error':{backgroundImage:'none',borderBottom:'2px solid #FF8D8D'},
  '.cm-scroller':{overflow:'auto',touchAction:'pan-x pan-y'},
});
const mauryaHighlight=HighlightStyle.define([
  {tag:tags.keyword,color:'#D7B977',fontWeight:'700'},
  {tag:[tags.string,tags.special(tags.string)],color:'#7CE6AE'},
  {tag:[tags.number,tags.bool],color:'#F3A6D2'},
  {tag:[tags.variableName,tags.propertyName],color:'#B8C5FF'},
  {tag:[tags.function(tags.variableName),tags.function(tags.propertyName)],color:'#77D4E8'},
  {tag:[tags.typeName,tags.className],color:'#C99AF2'},
  {tag:[tags.operator,tags.punctuation],color:'#D9DDF1'},
  {tag:[tags.comment,tags.lineComment,tags.blockComment],color:'#737B9D',fontStyle:'italic'},
  {tag:tags.invalid,color:'#FF8D8D',textDecoration:'underline'},
]);

let changeTimer=0;
const view=new EditorView({
  parent:document.querySelector('#script-editor')!,
  state:EditorState.create({
    doc:'',
    extensions:[
      lineNumbers(),highlightActiveLine(),highlightActiveLineGutter(),history(),cpp(),
      bracketMatching(),highlightSelectionMatches(),lintGutter(),autocompletion({override:[complete]}),
      syntaxHighlighting(mauryaHighlight),indentUnit.of('    '),theme,
      EditorView.contentAttributes.of({'aria-label':japanese?'Maurya Scriptコードエディター':'Maurya Script代码编辑器'}),
      keymap.of([...defaultKeymap,...historyKeymap,...completionKeymap,...searchKeymap,indentWithTab]),
      EditorView.updateListener.of(update=>{
        if(!update.docChanged)return;
        clearTimeout(changeTimer);
        changeTimer=window.setTimeout(()=>{
          const source=update.state.doc.toString();
          window.MauryaBridge?.onSourceChanged(source,update.state.doc.lines);
        },120);
      }),
    ],
  }),
});

function replaceAll(source:string){
  view.dispatch({changes:{from:0,to:view.state.doc.length,insert:source}});
}
function indentSource(source:string){
  let depth=0;
  return source.split(/\r?\n/).map(raw=>{
    const line=raw.trim();
    if(line.startsWith('}'))depth=Math.max(0,depth-1);
    const result=line?'    '.repeat(depth)+line:'';
    if(line.endsWith('{'))depth++;
    return result;
  }).join('\n');
}
function diagnostic(start:number,end:number,message:string):Diagnostic{
  const length=view.state.doc.length;
  return {from:Math.max(0,Math.min(start,length)),to:Math.max(0,Math.min(Math.max(end,start+1),length)),severity:'error',message};
}

window.MauryaScriptEditor={
  load(source){replaceAll(source);view.focus();},
  save(){return view.state.doc.toString();},
  run(){window.MauryaBridge?.onRunRequested(this.save());},
  undo(){cmUndo(view);},
  redo(){cmRedo(view);},
  format(){replaceAll(indentSource(view.state.doc.toString()));},
  insertWaitAfter(offset,millis){
    const position=Math.max(0,Math.min(offset,view.state.doc.length));
    const line=view.state.doc.lineAt(position);
    const indentation=/^\s*/.exec(line.text)?.[0]??'';
    const duration=millis%1000===0?`${millis/1000}s`:`${millis}ms`;
    view.dispatch({changes:{from:position,insert:`\n${indentation}wait(${duration});`}});
    view.focus();
  },
  showDiagnostic(start,end,message){
    view.dispatch(setDiagnostics(view.state,[diagnostic(start,end,message)]));
    this.focusRange(start,end);
  },
  clearDiagnostics(){view.dispatch(setDiagnostics(view.state,[]));},
  focusRange(start,end){
    const length=view.state.doc.length;
    const anchor=Math.max(0,Math.min(start,length));
    const head=Math.max(anchor,Math.min(end,length));
    view.dispatch({selection:{anchor,head},scrollIntoView:true});
    view.focus();
  },
};
