import vscode, { CancellationToken } from "vscode";
import {
    ConfigurationParams,
    LSPAny,
    LanguageClient,
    LanguageClientOptions,
    RequestHandler,
    ResponseError,
    ServerOptions,
} from "vscode-languageclient/node";
import which from "which";
import fs from "fs";

let outputChannel: vscode.OutputChannel;
export let client: LanguageClient | null = null;

export function activate(context: vscode.ExtensionContext) {
    outputChannel = vscode.window.createOutputChannel("VeMod Language Server");

    context.subscriptions.push(
        vscode.commands.registerCommand("vemod.vmdls.startRestart", async () => {
            if (!checkInstalled()) {
                return;
            }
    
            await stopClient();
            await startClient();
        }),
    );
}

export function deactivate() {
    return stopClient();
}

function checkInstalled(): boolean {
    const vmdlsPath = vscode.workspace.getConfiguration("vemod.vmdls").get<string>("path");
    if (!vmdlsPath) {
        vscode.window.showErrorMessage("This command cannot be run without setting 'vemod.vmdls.path'.", {
            modal: true,
        });
        return false;
    }
    return true;
}

export async function stopClient() {
    if (client) {
        await client.stop();
    }
    client = null;
}

async function startClient() {
    const vmdlsPath = getPath();

    const serverOptions: ServerOptions = {
        command: vmdlsPath,
        args: [],
    };

    const clientOptions: LanguageClientOptions = {
        documentSelector: [{ scheme: "file", language: "vmd" }],
        outputChannel,
        middleware: {
            workspace: {
                configuration: configurationMiddleware,
            },
        },
    };

    // Create the language client and start the client.
    client = new LanguageClient("vemod.vmdls", "VeMod Language Server", serverOptions, clientOptions);

    return client
        .start()
        .catch((error: unknown) => {
            const reason = error instanceof Error ? error.message : error;
            void vscode.window.showWarningMessage(`Failed to run VeMod Language Server (vmdls): ${reason}`);
            client = null;
        });
}

export function getPath(): string {
    const configuration = vscode.workspace.getConfiguration("vemod.vmdls");
    let path: string | null = configuration.get<string>("path") || null;
    // the string "vmdls" means lookup in PATH
    if (path === "vmdls") {
        path = which.sync(path, { nothrow: true });
    }
    const error = (msg: string) => {
        vscode.window.showErrorMessage(msg);
        return new Error(msg);
    };
    if (!path) {
        throw error(`Could not find ${path} in PATH`);
    }
    if (!fs.existsSync(path)) {
        throw error(`\`vemod.vmdls.path\` ${path} does not exist`);
    }
    try {
        fs.accessSync(path, fs.constants.R_OK | fs.constants.X_OK);
        return path;
    } catch {
        throw error(`\`vemod.vmdls.path\` ${path} is not an executable`);
    }
}

async function configurationMiddleware(
    params: ConfigurationParams,
    token: CancellationToken,
    next: RequestHandler<ConfigurationParams, LSPAny[], void>,
): Promise<LSPAny[] | ResponseError> {
    console.log("params", params);
    console.log("token", token);
    
    const result = await next(params, token);
    console.log("result", result);
    if (result instanceof ResponseError) {
        return result;
    }
    return result as unknown[];
}