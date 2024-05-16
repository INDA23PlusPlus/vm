import * as vscode from 'vscode';
import * as vmdls from './vmdls';

const vemodLanguageIds = [ "vemod", "blue" ];

export async function activate(context: vscode.ExtensionContext) {
    await vmdls.activate(context);

    context.subscriptions.push(
        vscode.commands.registerCommand('vemod.runFile', () => runVemodOnActiveDocument("")),
        vscode.commands.registerCommand('vemod.runFileForceJit', () => runVemodOnActiveDocument("-j full")),
        // TODO: transpile, compile, install
    );
}

function getVemodTerminal() {
    const name = "VeMod";
    const existing = vscode.window.terminals.find(term => term.name === name);
    if (existing) {
        return existing;
    }
    return vscode.window.createTerminal({ name: name });
}

// Returns the filename of the active document, or null if the active document is
// not VeMod or Blue source.
function getActiveFilename() {

    const activeEditor = vscode.window.activeTextEditor;
    if (!activeEditor) {
        vscode.window.showErrorMessage("VeMod: No active document");
        return null;
    }

    const document = activeEditor.document;
    if (!vemodLanguageIds.includes(document.languageId)) {
        vscode.window.showErrorMessage("VeMod: Active document is not VeMod assembly or Blue source");
        return null;
    }

    return document.fileName;
}

async function runVemodOnActiveDocument(extraArgs: string) {

    // TODO: window.showQuickPick for JIT options
    const activeEditor = vscode.window.activeTextEditor;
    if (!activeEditor) return;

    const filename = getActiveFilename();
    if (!filename) {
        return;
    }

    const args = ["clear && vemod", filename, extraArgs].join(" ");

    const saveStatus = activeEditor.document.save();
    if (!saveStatus) {
        vscode.window.showErrorMessage("VeMod: Failed to save document " + filename);
        return;
    }

    const terminal = getVemodTerminal();
    terminal.show(false);
    terminal.sendText(args, true);
}

export async function deactivate() {
    await vmdls.deactivate();
}
