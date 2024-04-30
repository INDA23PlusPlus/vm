import * as vscode from 'vscode';
import * as vmdls from './vmdls';

export async function activate(context: vscode.ExtensionContext) {
    await vmdls.activate(context);

    context.subscriptions.push(
        vscode.commands.registerCommand('vemod.helloWorld', () => {
            vscode.window.showInformationMessage('Hello World from vscode-vemod!');
        }),
    );
}

export async function deactivate() {
    await vmdls.deactivate();
}
