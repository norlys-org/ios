/**
 * Console Bridge JavaScript
 * 
 * This script intercepts all console methods (log, error, warn, info) and bridges them
 * to the native iOS app through WKScriptMessageHandler. This allows viewing web console
 * output in the native debugger.
 * 
 * Used in: WebViewController.swift
 */

function captureLog(type, args) {
    window.webkit.messageHandlers.console.postMessage({
        type: type,
        message: Array.from(args).map(arg => {
            try {
                return typeof arg === 'object' ? JSON.stringify(arg) : String(arg);
            } catch (e) {
                return String(arg);
            }
        })
    });
}

// Store original console methods
console._log = console.log;
console._error = console.error;
console._warn = console.warn;
console._info = console.info;

// Override console methods to capture and forward messages
console.log = function() { captureLog('log', arguments); console._log.apply(console, arguments); }
console.error = function() { captureLog('error', arguments); console._error.apply(console, arguments); }
console.warn = function() { captureLog('warn', arguments); console._warn.apply(console, arguments); }
console.info = function() { captureLog('info', arguments); console._info.apply(console, arguments); } 