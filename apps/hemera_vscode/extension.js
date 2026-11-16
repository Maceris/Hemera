/*
 * Hemera for VS Code: starts hemera-lsp for .hsc files, which shows the compiler's diagnostics as files are opened
 * and saved (docs/editor.md). The grammar and language configuration need no code.
 */
"use strict";

const vscode = require("vscode");
const { LanguageClient, TransportKind } = require("vscode-languageclient/node");

let client;

// What the server reads from initializationOptions, and from each change to the hemera settings
function serverSettings() {
    const settings = vscode.workspace.getConfiguration("hemera");
    return {
        compilerPath: settings.get("compilerPath"),
        root: settings.get("root"),
        arguments: settings.get("arguments"),
        checkerMemory: settings.get("checkerMemory"),
    };
}

async function startClient() {
    const server = vscode.workspace.getConfiguration("hemera").get("serverPath");
    client = new LanguageClient(
        "hemera",
        "Hemera",
        { command: server, transport: TransportKind.stdio },
        {
            documentSelector: [{ scheme: "file", language: "hemera" }],
            initializationOptions: serverSettings(),
            // Sends workspace/didChangeConfiguration with settings.hemera when they change
            synchronize: { configurationSection: "hemera" },
        });
    try {
        await client.start();
    } catch (error) {
        client = undefined;
        vscode.window.showErrorMessage(
            `Hemera: couldn't start ${server}: ${error.message}. Set hemera.serverPath to hemera-lsp.`);
    }
}

async function stopClient() {
    if (client !== undefined) {
        const stopping = client;
        client = undefined;
        await stopping.stop();
    }
}

async function activate(context) {
    context.subscriptions.push(vscode.workspace.onDidChangeConfiguration(async (event) => {
        // A different server is a different process
        if (event.affectsConfiguration("hemera.serverPath")) {
            await stopClient();
            await startClient();
        }
    }));
    await startClient();
}

async function deactivate() {
    await stopClient();
}

module.exports = { activate, deactivate };
