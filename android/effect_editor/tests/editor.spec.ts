import {expect, test, type Page} from '@playwright/test';

const responsiveViewports = [
  {width:320,height:360},
  {width:360,height:480},
  {width:360,height:552},
  {width:411,height:620},
  {width:800,height:480},
];

async function loadColourBlock(page: Page) {
  await page.evaluate(()=>window.MauryaEditor?.load(JSON.stringify({
    blocks:{languageVersion:0,blocks:[{
      type:'maurya_start',id:'responsive-start',next:{block:{
        type:'maurya_set_color',id:'responsive-colour',fields:{TARGET:'ALL',COLOR:'#E7FF30'},
      }},
    }]},
  })));
}

test('touch toolbox, serialization and compact controls work offline', async ({page}) => {
  await page.goto('/?lang=zh');
  await expect(page.locator('.blocklyToolboxCategory')).toHaveCount(13);
  for (const label of [
    '灯光','时间','变量','运算','判断','控制','状态',
    '算法','列表','传感器','音频','图案','函数',
  ]) {
    await expect(page.getByText(label,{exact:true})).toBeVisible();
  }

  const category=await page.getByText('灯光',{exact:true}).boundingBox();
  expect(category).not.toBeNull();
  await page.touchscreen.tap(category!.x+category!.width/2,category!.y+category!.height/2);
  await expect(page.locator('.blocklyToolboxFlyout')).toBeVisible();

  await page.evaluate(()=>window.MauryaEditor?.load(JSON.stringify({
    blocks:{languageVersion:0,blocks:[{type:'maurya_start',id:'start-test'}]},
  })));
  expect(await page.evaluate(()=>window.MauryaEditor?.save())).toContain('maurya_start');
  await expect(page.locator('#workspace-controls button')).toHaveCount(4);
  await expect(page.locator('.blocklyZoom')).toHaveCount(0);
  await expect(page.locator('.blocklyTrash')).toHaveCount(0);
  await expect(page.locator('#field-hit-targets')).toHaveCount(0);

  const vertical=await page.locator('.blocklyMainWorkspaceScrollbar.blocklyScrollbarVertical').boundingBox();
  expect(vertical).not.toBeNull();
  expect(vertical!.width).toBeLessThanOrEqual(12);
});

test('touch dragging empty workspace pans while block dragging still moves blocks', async ({page}) => {
  await page.goto('/?lang=zh');
  await page.evaluate(()=>window.MauryaEditor?.load(JSON.stringify({
    blocks:{languageVersion:0,blocks:[{type:'maurya_start',id:'drag-start',x:40,y:40}]},
  })));
  await page.waitForTimeout(100);

  const cdp=await page.context().newCDPSession(page);
  const block=page.locator('.blocklyDraggable[data-id="drag-start"]');
  const beforeBlock=await block.boundingBox();
  expect(beforeBlock).not.toBeNull();
  const blockX=beforeBlock!.x+beforeBlock!.width/2;
  const blockY=beforeBlock!.y+beforeBlock!.height/2;
  expect(await page.evaluate(({x,y})=>Boolean(document.elementFromPoint(x,y)?.closest('.blocklyDraggable')),{x:blockX,y:blockY})).toBe(true);
  await cdp.send('Input.dispatchTouchEvent',{
    type:'touchStart',
    touchPoints:[{x:blockX,y:blockY}],
  });
  for(let step=1;step<=5;step++) {
    await cdp.send('Input.dispatchTouchEvent',{
      type:'touchMove',
      touchPoints:[{x:blockX+16*step,y:blockY+10*step}],
    });
  }
  await cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});
  const afterBlock=await block.boundingBox();
  expect(afterBlock).not.toBeNull();
  expect(Math.abs(afterBlock!.x-beforeBlock!.x)).toBeGreaterThan(20);

  await page.evaluate(()=>window.MauryaEditor?.load(JSON.stringify({
    blocks:{languageVersion:0,blocks:[
      {type:'maurya_start',id:'pan-start',x:40,y:40},
      {type:'maurya_start',id:'pan-far',x:1500,y:900},
    ]},
  })));
  await page.waitForTimeout(100);
  await page.locator('#control-zoom-in').click();
  await page.locator('#control-zoom-in').click();
  const workspacePoint=await page.evaluate(()=>{
    const rect=document.querySelector<SVGElement>('.blocklyMainBackground')!.getBoundingClientRect();
    return {x:rect.left+rect.width*.65,y:rect.top+rect.height*.78};
  });
  const canvas=page.locator('.blocklyBlockCanvas').first();
  const beforePan=await canvas.getAttribute('transform');
  await cdp.send('Input.dispatchTouchEvent',{
    type:'touchStart',
    touchPoints:[{x:workspacePoint.x,y:workspacePoint.y}],
  });
  for(let step=1;step<=5;step++) {
    await cdp.send('Input.dispatchTouchEvent',{
      type:'touchMove',
      touchPoints:[{
        x:workspacePoint.x-24*step,
        y:workspacePoint.y-12*step,
      }],
    });
  }
  await cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});
  await expect.poll(()=>canvas.getAttribute('transform')).not.toBe(beforePan);
});

test('touch dragging a connected child detaches it without moving the parent block', async ({page}) => {
  await page.goto('/?lang=zh');
  await page.evaluate(()=>window.MauryaEditor?.load(JSON.stringify({
    blocks:{languageVersion:0,blocks:[{
      type:'maurya_start',id:'drag-parent',x:40,y:40,next:{block:{
        type:'maurya_wait',id:'drag-child',fields:{DURATION:1,UNIT:'SEC'},
      }},
    }]},
  })));
  await page.waitForTimeout(100);

  const cdp=await page.context().newCDPSession(page);
  const parent=page.locator('.blocklyDraggable[data-id="drag-parent"]');
  const child=page.locator('.blocklyDraggable[data-id="drag-child"]');
  const parentBefore=await parent.boundingBox();
  const childBefore=await child.boundingBox();
  expect(parentBefore).not.toBeNull();
  expect(childBefore).not.toBeNull();

  const startX=childBefore!.x+childBefore!.width*.75;
  const startY=childBefore!.y+childBefore!.height/2;
  await cdp.send('Input.dispatchTouchEvent',{
    type:'touchStart',touchPoints:[{x:startX,y:startY}],
  });
  for(let step=1;step<=6;step++) {
    await cdp.send('Input.dispatchTouchEvent',{
      type:'touchMove',
      touchPoints:[{x:startX+24*step,y:startY+14*step}],
    });
  }
  await cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});

  const parentAfter=await parent.boundingBox();
  const childAfter=await child.boundingBox();
  expect(parentAfter).not.toBeNull();
  expect(childAfter).not.toBeNull();
  expect(Math.abs(parentAfter!.x-parentBefore!.x)).toBeLessThan(2);
  expect(Math.abs(parentAfter!.y-parentBefore!.y)).toBeLessThan(2);
  expect(Math.abs(childAfter!.x-childBefore!.x)).toBeGreaterThan(40);
});

test('number field uses the mobile editor and persists its value', async ({page}) => {
  await page.goto('/?lang=zh');
  await page.evaluate(()=>window.MauryaEditor?.load(JSON.stringify({
    blocks:{languageVersion:0,blocks:[{
      type:'maurya_start',id:'start-wait',next:{block:{
        type:'maurya_wait',id:'wait-ten',fields:{DURATION:10,UNIT:'SEC'},
      }},
    }]},
  })));
  await page.waitForTimeout(100);
  const waitFields=page.locator('[data-id="wait-ten"] .blocklyEditableField');
  await expect(waitFields).toHaveCount(2);
  const numberBounds=await waitFields.first().boundingBox();
  expect(numberBounds).not.toBeNull();
  await page.touchscreen.tap(
    numberBounds!.x+numberBounds!.width/2,
    numberBounds!.y+numberBounds!.height/2,
  );
  await expect(page.locator('#field-editor')).toBeVisible();
  await expect(page.locator('#field-number-range')).toHaveAttribute('min','1');
  await expect(page.locator('#field-number-range')).toHaveAttribute('max','60');
  await expect(page.locator('#field-number-input')).toHaveAttribute('max','600');
  await page.locator('#field-number-input').fill('750');
  await page.locator('#field-editor-confirm').click();
  expect(await page.evaluate(()=>window.MauryaEditor?.save())).toContain('"DURATION":600');
});

test('number sliders use semantic ranges instead of the unbounded math fallback', async ({page}) => {
  await page.goto('/?lang=zh');
  await page.evaluate(()=>window.MauryaEditor?.load(JSON.stringify({
    blocks:{languageVersion:0,blocks:[{
      type:'maurya_start',id:'range-start',next:{block:{
        type:'maurya_set_pixel_hsv_value',id:'range-pixel',inputs:{
          GROUP:{shadow:{type:'math_number',id:'range-group',fields:{NUM:1}}},
          PIXEL:{shadow:{type:'math_number',id:'range-index',fields:{NUM:1}}},
          H:{shadow:{type:'math_number',id:'range-hue',fields:{NUM:210}}},
          S:{shadow:{type:'math_number',id:'range-saturation',fields:{NUM:255}}},
          V:{shadow:{type:'math_number',id:'range-value',fields:{NUM:180}}},
        },
      }},
    }]},
  })));
  await page.waitForTimeout(100);

  for(const [id,min,max] of [
    ['range-group','1','7'],
    ['range-index','1','6'],
    ['range-hue','0','359'],
    ['range-saturation','0','255'],
  ] as const) {
    const field=page.locator(`[data-id="${id}"] .blocklyEditableField`);
    const bounds=await field.boundingBox();
    expect(bounds).not.toBeNull();
    await page.touchscreen.tap(bounds!.x+bounds!.width/2,bounds!.y+bounds!.height/2);
    await expect(page.locator('#field-editor')).toBeVisible();
    await expect(page.locator('#field-number-range')).toHaveAttribute('min',min);
    await expect(page.locator('#field-number-range')).toHaveAttribute('max',max);
    await page.locator('#field-editor-cancel').click();
  }
});

test('HSV and HEX colour editor updates and persists the selected colour', async ({page}) => {
  await page.goto('/?lang=zh');
  await page.evaluate(()=>window.MauryaEditor?.load(JSON.stringify({
    blocks:{languageVersion:0,blocks:[{
      type:'maurya_start',id:'start-colour',next:{block:{
        type:'maurya_set_color',id:'set-colour',fields:{TARGET:'ALL',COLOR:'#FF3B6B'},
      }},
    }]},
  })));
  await page.waitForTimeout(100);

  const blockRoot=page.locator('[data-id="set-colour"]');
  const editableFields=blockRoot.locator('.blocklyEditableField');
  await expect(editableFields).toHaveCount(2);
  const colourField=editableFields.last();
  const colourBounds=await colourField.boundingBox();
  expect(colourBounds).not.toBeNull();
  await page.touchscreen.tap(
    colourBounds!.x+colourBounds!.width/2,
    colourBounds!.y+colourBounds!.height/2,
  );
  await expect(page.locator('#field-editor')).toBeVisible();
  await page.locator('#field-colour-hex').fill('#66CCFF');
  await page.locator('#field-colour-hex').dispatchEvent('change');
  await expect(page.locator('#field-colour-after')).toHaveCSS('background-color','rgb(102, 204, 255)');
  await page.locator('#field-editor-confirm').click();
  expect((await page.evaluate(()=>window.MauryaEditor?.save()))?.toUpperCase()).toContain('"COLOR":"#66CCFF"');
});

test('delete control enters explicit mode and deletes the next tapped block', async ({page}) => {
  await page.goto('/?lang=zh');
  await page.evaluate(()=>window.MauryaEditor?.load(JSON.stringify({
    blocks:{languageVersion:0,blocks:[{
      type:'maurya_start',id:'start-delete',next:{block:{
        type:'maurya_wait',id:'wait-delete',fields:{DURATION:500,UNIT:'MS'},
      }},
    }]},
  })));
  await page.locator('#control-delete').click();
  await expect(page.locator('#control-delete')).toHaveClass(/is-active/);
  const wait=await page.locator('.blocklyDraggable[data-id="wait-delete"]').boundingBox();
  expect(wait).not.toBeNull();
  await page.touchscreen.tap(wait!.x+12,wait!.y+12);
  await expect.poll(async()=>page.evaluate(()=>window.MauryaEditor?.save())).not.toContain('wait-delete');
});

test('Japanese toolbox and advanced blocks are localized', async ({page}) => {
  await page.goto('/?lang=ja');
  for (const label of ['ライト','時間','変数','演算','条件','制御','状態']) {
    await expect(page.getByText(label,{exact:true})).toBeVisible();
  }
});

test('42-pixel Blockly targets serialize without losing expressions', async ({page}) => {
  await page.goto('/?lang=zh');
  await page.evaluate(()=>window.MauryaEditor?.load(JSON.stringify({
    blocks:{languageVersion:0,blocks:[{
      type:'maurya_start',id:'pixel-start',next:{block:{
        type:'maurya_set_pixel_at_color_value',id:'pixel-at',
        inputs:{
          INDEX:{shadow:{type:'math_number',fields:{NUM:42}}},
          COLOR:{shadow:{type:'maurya_colour_literal',fields:{COLOR:'#1677FF'}}},
        },
        next:{block:{
          type:'maurya_set_all_pixels_hsv_value',id:'all-pixels-hsv',
          inputs:{
            H:{shadow:{type:'math_number',fields:{NUM:210}}},
            S:{shadow:{type:'math_number',fields:{NUM:255}}},
            V:{shadow:{type:'math_number',fields:{NUM:180}}},
          },
        }},
      }},
    }]},
  })));
  await page.waitForTimeout(100);
  const saved=await page.evaluate(()=>window.MauryaEditor?.save());
  expect(saved).toContain('maurya_set_pixel_at_color_value');
  expect(saved).toContain('maurya_set_all_pixels_hsv_value');
  expect(saved).toContain('"NUM":42');
  expect(saved?.toUpperCase()).toContain('#1677FF');

  const category=await page.getByText('灯光',{exact:true}).boundingBox();
  expect(category).not.toBeNull();
  await page.touchscreen.tap(category!.x+category!.width/2,category!.y+category!.height/2);
  await expect(page.getByText(/全部42颗/).first()).toBeVisible();
});

test('one-click fix inserts a wait after the invisible loop-tail colour', async ({page}) => {
  await page.goto('/?lang=zh');
  await page.evaluate(()=>window.MauryaEditor?.load(JSON.stringify({
    blocks:{languageVersion:0,blocks:[{
      type:'maurya_start',id:'start',next:{block:{
        type:'maurya_forever',id:'loop',inputs:{DO:{block:{
          type:'maurya_set_color',id:'red',fields:{TARGET:'ALL',COLOR:'#FF0000'},next:{block:{
            type:'maurya_wait',id:'red-wait',fields:{DURATION:2,UNIT:'SEC'},next:{block:{
              type:'maurya_set_color',id:'blue',fields:{TARGET:'ALL',COLOR:'#0000FF'},
            }},
          }},
        }}},
      }},
    }]},
  })));
  expect(await page.evaluate(()=>window.MauryaEditor?.insertWaitAfter('blue',2000))).toBe(true);
  const saved=await page.evaluate(()=>window.MauryaEditor?.save());
  expect(saved).toContain('"id":"blue"');
  expect(saved).toContain('"DURATION":2');
  expect(saved).toContain('"UNIT":"SEC"');
});

test('Maurya Script editor stays offline, formats and inserts a suggested wait', async ({page}) => {
  await page.goto('/script.html?lang=zh');
  const source=`effect "test" {
forever {
all.color("#FF0000");
wait(2s);
all.color("#0000FF");
}
}`;
  await page.evaluate(value=>window.MauryaScriptEditor.load(value),source);
  await expect(page.locator('.cm-editor')).toBeVisible();
  await page.evaluate(()=>window.MauryaScriptEditor.format());
  let saved=await page.evaluate(()=>window.MauryaScriptEditor.save());
  expect(saved).toContain('    forever {');
  const offset=saved.indexOf('all.color("#0000FF");')+'all.color("#0000FF");'.length;
  await page.evaluate(value=>window.MauryaScriptEditor.insertWaitAfter(value,2000),offset);
  saved=await page.evaluate(()=>window.MauryaScriptEditor.save());
  expect(saved).toContain('wait(2s);');
  await page.evaluate(()=>window.MauryaScriptEditor.showDiagnostic(0,6,'test error'));
  await expect(page.locator('.cm-lintRange-error')).toBeVisible();
  await page.screenshot({path:'test-results/maurya-script-editor.png',fullPage:true});
});

test('Maurya Script run forwards the exact current source to the native bridge', async ({page}) => {
  await page.goto('/script.html?lang=zh');
  const source=`effect "run" {
    all.color("#39C5BB");
    wait(500ms);
  }`;
  await page.evaluate(value=>{
    window.MauryaScriptEditor.load(value);
    let received:string|undefined;
    window.MauryaBridge={
      onSourceChanged(){},
      onRunRequested(document){received=document;},
      onHaptic(){},
    };
    window.MauryaScriptEditor.run();
    (window as typeof window&{__receivedRun?:string}).__receivedRun=received;
  },source);
  expect(await page.evaluate(()=>(window as typeof window&{__receivedRun?:string}).__receivedRun)).toBe(source);
});

for (const viewport of responsiveViewports) {
  test(`colour editor remains reachable at ${viewport.width}x${viewport.height}`, async ({page}) => {
    await page.setViewportSize(viewport);
    await page.goto('/?lang=zh');
    await loadColourBlock(page);
    await page.evaluate(()=>window.MauryaEditor?.editField('responsive-colour','COLOR'));

    await expect(page.locator('#field-editor-title')).toHaveText('修改颜色');
    const geometry=await page.evaluate(()=>{
      const modal=document.querySelector<HTMLElement>('#field-editor')!;
      const panel=document.querySelector<HTMLElement>('.field-editor__panel')!;
      const actions=document.querySelector<HTMLElement>('.field-editor__actions')!;
      const content=document.querySelector<HTMLElement>('#field-editor-colour')!;
      const title=document.querySelector<HTMLElement>('#field-editor-title')!;
      const viewportHeight=window.visualViewport?.height??window.innerHeight;
      const panelRect=panel.getBoundingClientRect();
      const actionRect=actions.getBoundingClientRect();
      const titleRect=title.getBoundingClientRect();
      return {
        modalHeight:modal.getBoundingClientRect().height,
        panelTop:panelRect.top,
        panelBottom:panelRect.bottom,
        titleTop:titleRect.top,
        actionsBottom:actionRect.bottom,
        viewportHeight,
        contentScrollable:content.scrollHeight>content.clientHeight,
        pageOverflow:document.documentElement.scrollWidth-document.documentElement.clientWidth,
      };
    });
    expect(geometry.modalHeight).toBeLessThanOrEqual(geometry.viewportHeight+1);
    expect(geometry.panelTop).toBeGreaterThanOrEqual(-1);
    expect(geometry.titleTop).toBeGreaterThanOrEqual(-1);
    expect(geometry.panelBottom).toBeLessThanOrEqual(geometry.viewportHeight+1);
    expect(geometry.actionsBottom).toBeLessThanOrEqual(geometry.viewportHeight+1);
    expect(geometry.pageOverflow).toBeLessThanOrEqual(0);

    const content=page.locator('#field-editor-colour');
    await content.evaluate(element=>element.scrollTop=element.scrollHeight);
    await expect(page.locator('#field-colour-presets')).toBeVisible();
    await expect(page.locator('#field-editor-confirm')).toBeVisible();
    await content.evaluate(element=>element.scrollTop=0);
    await expect(page.locator('#field-colour-before')).toBeVisible();
    await page.screenshot({
      path:`test-results/colour-editor-${viewport.width}x${viewport.height}.png`,
      fullPage:true,
    });
  });
}

test('field editors stay bounded after viewport and keyboard-style resize', async ({page}) => {
  await page.setViewportSize({width:360,height:552});
  await page.goto('/?lang=zh');
  await page.evaluate(()=>window.MauryaEditor?.load(JSON.stringify({
    blocks:{languageVersion:0,blocks:[{
      type:'maurya_start',id:'resize-start',next:{block:{
        type:'maurya_wait',id:'resize-wait',fields:{DURATION:500,UNIT:'MS'},
      }},
    }]},
  })));
  await page.evaluate(()=>window.MauryaEditor?.editField('resize-wait','DURATION'));
  await page.setViewportSize({width:360,height:360});
  await expect(page.locator('#field-number-input')).toBeVisible();
  await expect(page.locator('#field-editor-confirm')).toBeVisible();
  const bounded=await page.evaluate(()=>{
    const panel=document.querySelector<HTMLElement>('.field-editor__panel')!.getBoundingClientRect();
    const viewportHeight=window.visualViewport?.height??window.innerHeight;
    return panel.top>=-1 && panel.bottom<=viewportHeight+1;
  });
  expect(bounded).toBe(true);
  await page.locator('#field-number-input').fill('900');
  await page.locator('#field-editor-confirm').click();
  expect(await page.evaluate(()=>window.MauryaEditor?.save())).toContain('"DURATION":900');
});
