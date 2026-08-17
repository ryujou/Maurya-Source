#if os(iOS)
    import Foundation

    enum EditorBootstrap {
        static func source(nonce: String, editor: EditorKind) -> String {
            let nonceLiteral = javascriptString(nonce)
            let editorLiteral = javascriptString(editor.rawValue)
            return """
                (() => {
                  'use strict';
                  const VERSION = 1;
                  const NONCE = \(nonceLiteral);
                  const EDITOR = \(editorLiteral);
                  let sequence = 0;
                  const requestID = () => `web-${Date.now()}-${++sequence}`;
                  const post = (type, payload, id = requestID()) => {
                    window.webkit.messageHandlers.mauryaBridge.postMessage({version: VERSION, nonce: NONCE, requestID: id, type, payload});
                  };
                  const documentPayload = value => ({document: String(value ?? '')});
                  Object.defineProperty(window, 'MauryaBridge', {configurable: false, writable: false, value: Object.freeze({
                    onWorkspaceChanged: (document, count) => post('workspaceChanged', {document: String(document), count: Number(count)}),
                    onSourceChanged: (document, lines) => post('sourceChanged', {document: String(document), lines: Number(lines)}),
                    onSaveRequested: document => post('saveRequested', documentPayload(document)),
                    onRunRequested: document => post('runRequested', documentPayload(document)),
                    onHaptic: kind => post('haptic', {kind: String(kind)})
                  })});
                  const api = () => EDITOR === 'blocks' ? window.MauryaEditor : window.MauryaScriptEditor;
                  Object.defineProperty(window, '__mauryaNativeReceive', {configurable: false, writable: false, value: envelope => {
                    if (!envelope || envelope.version !== VERSION || envelope.nonce !== NONCE || envelope.type !== 'command') return false;
                    const id = String(envelope.requestID || '');
                    const command = envelope.payload?.command;
                    const args = envelope.payload?.arguments || {};
                    const target = api();
                    if (!target) return false;
                    let value = null;
                    switch (command) {
                      case 'load': case 'import': value = target.load(String(args.document ?? '')); break;
                      case 'export': value = target.save(); break;
                      case 'undo': value = target.undo(); break;
                      case 'redo': value = target.redo(); break;
                      case 'resize': value = target.resize?.(); break;
                      case 'fit': value = target.fit?.(); break;
                      case 'run': value = target.run?.(); break;
                      case 'editField': value = target.editField?.(String(args.blockID ?? ''), String(args.fieldName ?? '')); break;
                      case 'insertWaitAfter': value = target.insertWaitAfter?.(EDITOR === 'blocks' ? String(args.target ?? '') : Number(args.target ?? 0), Number(args.milliseconds)); break;
                      case 'diagnostic': value = target.showDiagnostic?.(Number(args.start), Number(args.end), String(args.message ?? '')); break;
                      case 'clearDiagnostics': value = target.clearDiagnostics?.(); break;
                      default: return false;
                    }
                    post('response', {command, value: value === undefined ? null : value}, id);
                    return true;
                  }});
                  const announceReady = () => {
                    if (api()) post('ready', {editor: EDITOR});
                    else setTimeout(announceReady, 25);
                  };
                  addEventListener('DOMContentLoaded', announceReady, {once: true});
                })();
                """
        }

        private static func javascriptString(_ value: String) -> String {
            let data = try? JSONEncoder().encode(value)
            return data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        }
    }
#endif
