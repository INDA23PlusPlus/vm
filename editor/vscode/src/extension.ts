import * as vscode from 'vscode';
import * as vmdls from './vmdls';

export function activate(context: vscode.ExtensionContext) {
    vmdls.activate(context);

    context.subscriptions.push(
        vscode.commands.registerCommand('vemod.helloWorld', () => {
            vscode.window.showInformationMessage('Hello World from vscode-vemod!');
        }),
    );
}

export function deactivate() {
    vmdls.deactivate();
}
