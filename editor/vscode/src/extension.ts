import * as vscode from 'vscode';
import * as vmdls from './vmdls';
import * as child_process from 'child_process';

const vemodLanguageIds = [ "vemod", "blue" ];
let outputChannel: vscode.OutputChannel;

// TODO: replace with configuration
const vemodCommand = "vemod";

export async function activate(context: vscode.ExtensionContext) {
    await vmdls.activate(context);

    context.subscriptions.push(
        vscode.commands.registerCommand('vemod.runFile', () => runVemodOnActiveDocument("")),
        vscode.commands.registerCommand('vemod.runFileForceJit', () => runVemodOnActiveDocument("-j full")),
        vscode.commands.registerCommand('vemod.transpileFile', () => transpileFile()),
        // TODO: transpile, compile, install
    );

    outputChannel = vscode.window.createOutputChannel("VeMod");
}

function getVemodTerminal() {
    const name = "VeMod";
    const existing = vscode.window.terminals.find(term => term.name === name);
    if (existing) {
        return existing;
    }
    return vscode.window.createTerminal({ name: name });
}

// Returns the document open in the currently active editor.
// Returns null if there is no active editor or if the document is not VeMod-supported.
function getActiveVemodDocument() {
    const editor = vscode.window.activeTextEditor;
    if (!editor) {
        vscode.window.showErrorMessage("VeMod: No active document");
        return null;
    }

    const document = editor.document;
    if (!vemodLanguageIds.includes(document.languageId)) {
        vscode.window.showErrorMessage("VeMod: Active document is not VeMod assembly or Blue source");
        return null;
    }

    return document;
}

async function runVemodOnActiveDocument(extraArgs: string) {

    const document = getActiveVemodDocument();
    if (!document) {
        return;
    }

    const args = [`clear && ${vemodCommand}`, document.fileName, extraArgs].join(" ");

    if (document.isDirty) {
    const saveStatus = document.save();
        if (!saveStatus) {
            vscode.window.showErrorMessage("VeMod: Failed to save document " + document.fileName);
            return;
        }
    }

    const terminal = getVemodTerminal();
    terminal.show(false);
    terminal.sendText(args, true);
}

function stripExtension(path: string) {
    return path.replace(/\.[^/.]+$/, "");
}

async function transpileFile() {

    const document = getActiveVemodDocument();
    if (!document) {
        return;
    }

    const args = [ "--transpile", "--no-color", document.fileName ];
    const child = child_process.spawn(vemodCommand, args);

    child.on('error', err => vscode.window.showErrorMessage(`VeMod: Unable to run command ${vemodCommand}: ${err.toString()}`));

    child.on('exit', (code, signal) => {
        if (code != null) {
            if (code > 0) {

                // Failure
                // Display stderr in VeMod terminal
                //
                vscode.window.showErrorMessage(`VeMod: ${vemodCommand} exited with status ${code}`);
                child.stderr.setEncoding('utf8');

                outputChannel.clear();

                let chunk;
                while (null !== (chunk = child.stderr.read())) {
                    outputChannel.append(chunk);
                }

                outputChannel.show(false);

            } else {

                // Success
                // Open transpiled document in split editor
                //
                const outputPath = `${stripExtension(document.fileName)}.vmd`;
                vscode.workspace.openTextDocument(outputPath).then(result =>
                   vscode.window.showTextDocument(result, vscode.ViewColumn.Beside, false)
                );
            }
        } else {

            vscode.window.showErrorMessage(`VeMod: ${vemodCommand} received signal ${signal}`);
        }
    });
}

export async function deactivate() {
    await vmdls.deactivate();
}
