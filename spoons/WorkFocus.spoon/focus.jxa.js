#!/usr/bin/env osascript -l JavaScript

const targetMode = 'Work';
const action = argv[0] === 'on';
const $attr = Ref();
const $value = Ref();
const $windows = Ref();
const $children = Ref();

function fail(message) {
  console.log(`[WorkFocus] ${message}`);
  return 1;
}

function waitFor(getValue, predicate) {
  const deadline = Date.now() + 2000;
  while (Date.now() <= deadline) {
    getValue();
    if (predicate()) return true;
    delay(0.1);
  }
  return false;
}

function run() {
  const running = $.NSRunningApplication.runningApplicationsWithBundleIdentifier(
    'com.apple.controlcenter',
  ).firstObject;
  if (!running) return fail('Control Center is not running');

  const app = $.AXUIElementCreateApplication(running.processIdentifier);
  $.AXUIElementCopyAttributeValue(app, 'AXChildren', $children);
  const menuExtras = $children[0].js[0];
  $.AXUIElementCopyAttributeValue(menuExtras, 'AXChildren', $children);
  const controlCenter = $children[0].js.find((child) => {
    $.AXUIElementCopyAttributeValue(child, 'AXIdentifier', $attr);
    return $attr[0].js == 'com.apple.menuextra.controlcenter';
  });
  if (!controlCenter) return fail('Control Center menu item not found');
  $.AXUIElementPerformAction(controlCenter, 'AXPress');

  if (!waitFor(
    () => $.AXUIElementCopyAttributeValue(app, 'AXWindows', $windows),
    () => typeof $windows[0] == 'function' && ($windows[0].js.length ?? 0) > 0,
  )) return fail('Control Center did not open');

  $.AXUIElementCopyAttributeValue($windows[0].js[0], 'AXChildren', $children);
  const modulesGroup = $children[0].js.find((child) => {
    $.AXUIElementCopyAttributeValue(child, 'AXRole', $attr);
    return $attr[0].js == 'AXGroup';
  });
  if (!modulesGroup) return fail('Control Center modules not found');

  $.AXUIElementCopyAttributeValue(modulesGroup, 'AXChildren', $children);
  const focusModes = $children[0].js.find((child) => {
    $.AXUIElementCopyAttributeValue(child, 'AXIdentifier', $attr);
    return $attr[0].js == 'controlcenter-focus-modes';
  });
  if (!focusModes) return fail('Focus module not found');

  $.AXUIElementPerformAction(
    focusModes,
    'Name:show details\nTarget:0x0\nSelector:(null)',
  );

  if (!waitFor(
    () => $.AXUIElementCopyAttributeValue(modulesGroup, 'AXChildren', $children),
    () => typeof $children[0] == 'function' && ($children[0].js.length ?? 0) > 0,
  )) return fail('Focus options did not open');

  const options = $children[0].js.find((child) => {
    $.AXUIElementCopyAttributeValue(child, 'AXRole', $attr);
    return $attr[0].js == 'AXScrollArea';
  });
  if (!options) return fail('Focus options not found');

  $.AXUIElementCopyAttributeValue(options, 'AXChildren', $children);
  const toggle = $children[0].js
    .filter((child) => {
      $.AXUIElementCopyAttributeValue(child, 'AXRole', $attr);
      return $attr[0].js == 'AXCheckBox';
    })
    .find((child) => {
      $.AXUIElementCopyAttributeValue(child, 'AXAttributedDescription', $attr);
      if (!$attr[0]) return false;
      return `${$attr[0].string.js}`.toLowerCase() == targetMode.toLowerCase();
    });
  if (!toggle) return fail(`Focus mode '${targetMode}' not found`);

  $.AXUIElementCopyAttributeValue(toggle, 'AXValue', $value);
  const enabled = Boolean($value[0].js);
  if (enabled != action) $.AXUIElementPerformAction(toggle, 'AXPress');

  $.CGEventPost($.kCGHIDEventTap, $.CGEventCreateKeyboardEvent(null, 53, true));
  return 0;
}

ObjC.import('Cocoa');
ObjC.bindFunction('AXUIElementPerformAction', ['int', ['id', 'id']]);
ObjC.bindFunction('AXUIElementCreateApplication', ['id', ['unsigned int']]);
ObjC.bindFunction('AXUIElementCopyAttributeValue', ['int', ['id', 'id', 'id*']]);
ObjC.bindFunction('CGEventCreateKeyboardEvent', ['id', ['id', 'unsigned short', 'bool']]);
ObjC.bindFunction('CGEventPost', ['void', ['unsigned int', 'id']]);

const result = run();
if (result !== 0) throw new Error('Unable to update Focus');
