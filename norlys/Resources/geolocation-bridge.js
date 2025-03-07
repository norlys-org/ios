/**
 * Geolocation Bridge JavaScript
 * 
 * This script overrides the browser's native geolocation API to bridge location requests
 * to the native iOS app. This allows the web app to request location data through
 * the standard web geolocation API while actually using native iOS location services.
 * 
 * Used in: WebViewController.swift, LocationScriptMessageHandler.swift
 */

(function() {
    // Storage for callback functions
    window._geolocationCallbacks = {};
    window._geolocationWatchers = {};
    let watchId = 0;
    
    // Override getCurrentPosition
    navigator.geolocation.getCurrentPosition = function(success, error, options) {
        const callbackId = Date.now().toString();
        window._geolocationCallbacks[callbackId] = { success, error };
        window.webkit.messageHandlers.location.postMessage({
            action: 'getCurrentPosition',
            callbackId: callbackId,
            options: options
        });
    };
    
    // Override watchPosition
    navigator.geolocation.watchPosition = function(success, error, options) {
        watchId++;
        window._geolocationWatchers[watchId] = { success, error };
        window.webkit.messageHandlers.location.postMessage({
            action: 'watchPosition',
            watchId: watchId,
            options: options
        });
        return watchId;
    };
    
    // Override clearWatch
    navigator.geolocation.clearWatch = function(id) {
        delete window._geolocationWatchers[id];
        window.webkit.messageHandlers.location.postMessage({
            action: 'clearWatch',
            watchId: id
        });
    };
})(); 