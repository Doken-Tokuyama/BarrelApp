//
//  BLImporter.swift
//  BarrelApp
//
//  Created by Thanos Siopoudis on 03/09/2014.
//  Copyright (c) 2014 AppCake Limited. All rights reserved.
//

import Cocoa

class BLImporter:NSObject, BLOperationDelegate, SSZipArchiveDelegate {
    var didMountSourceVolume:Bool = false;
    var sourceURL:NSURL?
    var importWindowController:BLImportWindowController?
    var scanQueue:NSOperationQueue?
    dynamic var installerURLs:NSArray = NSArray();
    dynamic var enginesList:NSArray = NSArray();
    var test:String = "Uninitialised";
    dynamic var currentImportIsIndeterminate:Bool = true;
    dynamic var currentImportValue:Int64 = 0;
    dynamic var currentImportMax:Int64 = 100;
    dynamic var currentImportAnimate:Bool = false;
    dynamic var currentStageName:String = "None";
    var downloadedEngine:NSURL?
    
    
    // MARK: Enum Types
    enum BLImportStage:Int {
        case BLImportWaitingForSource = 0
        case BLImportLoadingSource = 1
        case BLImportReadyToFetchEnginesList = 2
        case BLImportWaitingForInstaller = 3
        case BLImportReadyToLaunchInstaller = 4
        case BLImportRunningInstaller = 5
        case BLImportReadyToLookupRecipe = 6
        case BLImportSearchingForRecipe = 7
        case BLImportDownloadingRecipe = 8
        case BLImportReadyToDownloadEngine = 9
        case BLImportDownloadingEngine = 10
        case BLImportReadyToDownloadWinetricks = 11
        case BLImportDownloadingWinetricks = 12
        case BLImportReadyToDownloadSupportingFiles = 13
        case BLImportDownloadingSupportingFiles = 14
        case BLImportCleaningUp = 15
        case BLImportFinished = 16
    }
    
    enum BLSourceFileImportType {
        case BLImportTypeUnknown
        case BLImportTypePreinstalledGame
        case BLImportTypeMountedVolume
        case BLImportTypeDiskImage
        case BLImportTypeExecutable
        case BLImportTypeFolder
    }
    
    dynamic private(set) var BLImportStageStateRaw:Int = 0;
    var importStage:BLImportStage {
        didSet {
            BLImportStageStateRaw = importStage.rawValue
        }
    }
    
    override init() {
        self.scanQueue = NSOperationQueue();
        self.importStage = BLImportStage.BLImportWaitingForSource
        
        super.init();
    }
    
    override class func automaticallyNotifiesObserversForKey(key: String) -> Bool {
        return true;
    }
    
    // MARK: - Class Methods
    class func acceptedSourceTypes() -> NSSet? {
        var types:NSSet? = nil;
        if (types == nil) {
            if let unwrappedTypes = BLFileTypes.OSXMountableVolumeTypes() {
                types = unwrappedTypes.setByAddingObject("public.folder");
            }
        }
        
        return types;
    }
    
    class func preferredSourceURLForURL(URL:NSURL?) -> NSURL? {
        var workspace:NSWorkspace = NSWorkspace.sharedWorkspace();
        
        if (URL != nil) {
            if (workspace.typeOfVolumeAtURL(URL!) == BLAudioCDVolumeType) {
                var dataVolumeURL:NSURL? = workspace.dataVolumeOfAudioCDAtURL(URL!);
                if (dataVolumeURL != nil) {
                    return dataVolumeURL;
                }
            }
        }
        
        return URL;
    }
    
    // MARK: - Instance Methods
    func importFromSourceURL(URL:NSURL) {
        var readError:NSError? = nil;
        var readSucceeded:Bool = self.readFromURL(URL, typeName:"", error: &readError);
        
        if (!readSucceeded) {
            self.sourceURL = nil;
            self.importStage = BLImportStage.BLImportWaitingForSource;
            
            if (readError != nil) {
                var alert:NSAlert = NSAlert(error: readError!);
                alert.beginSheetModalForWindow(self.windowForSheet(), completionHandler: nil);
            }
        }
    }
    
    func readFromURL(absoluteURL:NSURL?, typeName:String, inout error:NSError?) -> Bool {
        assert(absoluteURL != nil, "No URL provided");
        
        self.didMountSourceVolume = false;
        var prefferedURL:NSURL? = BLImporter.preferredSourceURLForURL(absoluteURL);
        if (prefferedURL == nil) {
            return false;
        }
        
        self.sourceURL = prefferedURL;
        var scan:BLInstallerScan = BLInstallerScan.scanWithBasePath(prefferedURL!.path!) as BLInstallerScan;
        scan.delegate = self;
        scan.didFinishSelector = "installerScanDidFinish:";
        scan.didFinishClosure = self.installerScanDidFinish;
        
        self.scanQueue?.addOperation(scan);
        self.importStage = BLImportStage.BLImportLoadingSource;
        
        return true;
    }
    
    func windowForSheet() -> NSWindow {
        var importWindow:NSWindow = self.importWindowController!.window!;
        return importWindow;
    }
    
    func installerScanDidFinish(notification:NSNotification) {
        var scan:BLInstallerScan = notification.object as BLInstallerScan;
        
        if (scan.succeeded) {
            self.sourceURL = NSURL(fileURLWithPath: scan.recommendedSourcePath);
            self.didMountSourceVolume = false;
            
            self.installerURLs = self.sourceURL!.URLsByAppendingPaths(scan.matchingPaths);
            
            if (self.installerURLs.count > 0) {
                // Setup a new operation to fetch the engines list
                var fetchEngines:BLRemoteEngineList = BLRemoteEngineList();
                fetchEngines.delegate = self;
                fetchEngines.didFinishSelector = "fetchEnginesDidFinish:";
                fetchEngines.didFinishClosure = self.fetchEnginesDidFinish;
                
                self.scanQueue?.addOperation(fetchEngines);
//                self.importStage = BLImportStage.BLImportReadyToFetchEnginesList;
            }
            else {
                // We failed, so show a message and go back to waiting for source
                self.importStage = BLImportStage.BLImportWaitingForSource;
            }
        }
        else {
            // We failed, so show a message and go back to waiting for source
            self.importStage = BLImportStage.BLImportWaitingForSource;
        }
    }
    
    func fetchEnginesDidFinish(notification:NSNotification) {
        var fetchEngines:BLRemoteEngineList = notification.object as BLRemoteEngineList;
        
        if (fetchEngines.succeeded) {
            if let detectedEngines = fetchEngines.engineList {
                self.enginesList = detectedEngines;
                self.importStage = BLImportStage.BLImportWaitingForInstaller;
                NSApp.requestUserAttention(NSRequestUserAttentionType.InformationalRequest);
            }
            else {
                // We failed, so show a message and go back to waiting for source
                self.importStage = BLImportStage.BLImportWaitingForSource;
            }
        }
        else {
            // We failed, so show a message and go back to waiting for source
            self.importStage = BLImportStage.BLImportWaitingForSource;
        }
    }
    
    func launchInstallerAtURL(URL:NSURL?, withEngine engine:Engine) {
        // Run some sanity checks
        assert(URL != nil, "No URL specified");
        assert(self.sourceURL != nil, "No source URL for the import has been chosen");
        
        // If the engine is stored remotely, download it from the remote server
        if (engine.isRemote) {
            self.currentImportIsIndeterminate = true;
            self.currentImportAnimate = true;
            self.importStage = BLImportStage.BLImportDownloadingEngine;
            self.downloadSelectedEngine(engine);
        }
    }
    
    // MARK: - Engine related methods
    func downloadSelectedEngine(engine:Engine) {
        // Setup the progress indicators
        self.currentStageName = "Downloading Engine: \(engine.Name)...";
        self.currentImportIsIndeterminate = false;
        self.currentImportAnimate = false;
        self.currentImportValue = 0;
        self.currentImportMax = 100;
        
        var engineSourceURL:NSURL? = NSURL(string: "http://localhost:3000\(engine.Path)");
        // Always save our engines in the games URL, under a hidden folder
        var engineCache:NSURL = AppDelegate.preferredGamesFolderURL().URLByAppendingPathComponent(".engines", isDirectory: true);
        var engineDownloader:BLFileDownloader = BLFileDownloader(fromURL: engineSourceURL, toURL: engineCache);
        engineDownloader.didFinishCallback = self.didFinishDownload;
        
        self.currentImportMax = engineDownloader.totalBytes;
        self.currentImportValue = engineDownloader.currentBytes;
        engineDownloader.startDownoad();
    }
    
    func didFinishDownload(resultCode:Int, downloadedFileURL:NSURL) {
        if (resultCode == 1) {
            self.downloadedEngine = downloadedFileURL;
            // Start recipe download
            self.downloadRecipe();
        }
    }
    
    func downloadRecipe() {
        // Skip recipes for now
        // TODO: Recipes not implemented
        
        self.currentStageName = "Downloading Recipe...";
        self.currentImportIsIndeterminate = true;
        self.currentImportAnimate = true;
        self.importStage = BLImportStage.BLImportDownloadingRecipe;
        self.downloadSupportingFiles();
    }
    
    func downloadSupportingFiles() {
        // Skip supporting files
        // TODO: Supporting Files not implemented
        
        self.currentStageName = "Downloading Supporting Files...";
        self.currentImportIsIndeterminate = true;
        self.currentImportAnimate = true;
        self.importStage = BLImportStage.BLImportDownloadingSupportingFiles;
        self.downloadWinetricks();
    }
    
    func downloadWinetricks() {
        // Skip Winetricks for now
        // TODO: Winetricks not implemented
        
        self.currentStageName = "Downloading Winetricks...";
        self.currentImportIsIndeterminate = true;
        self.currentImportAnimate = true;
        self.importStage = BLImportStage.BLImportDownloadingWinetricks;
        self.buildBundleAndRunSetup();
    }
    
    func buildBundleAndRunSetup() {
        self.currentStageName = "Preparing Bundle...";
        self.currentImportIsIndeterminate = true;
        self.currentImportAnimate = true;
        self.importStage = BLImportStage.BLImportRunningInstaller;
        
        // Let's create a copy of our incuded Bundle in the .tmp directory
        // If the tmp directory exists, clean it up first; we don't want too much junk in there
        var tempDirURL:NSURL = AppDelegate.preferredGamesFolderURL().URLByAppendingPathComponent(".tmp", isDirectory: true);
        if (NSFileManager.defaultManager().fileExistsAtPath(tempDirURL.path!)) {
            var fileArray:NSArray = NSFileManager.defaultManager().contentsOfDirectoryAtURL(tempDirURL, includingPropertiesForKeys: [ NSURLNameKey ], options: NSDirectoryEnumerationOptions.allZeros, error: nil)!;
            for fURL in fileArray {
                var fileURL:NSURL = fURL as NSURL;
                NSFileManager.defaultManager().removeItemAtURL(fileURL, error: nil);
            }
        }
        
        // TODO: Do some error handling here, in case the copy fails for some reason
        let bundleTemplateURL:NSURL = NSBundle.mainBundle().resourceURL!.URLByAppendingPathComponent("BarrelBundle.app");
        NSFileManager.defaultManager().copyItemAtURL(bundleTemplateURL, toURL: tempDirURL.URLByAppendingPathComponent("BarrelBundle.app"), error: nil);
        let newBundleURL:NSURL = tempDirURL.URLByAppendingPathComponent("BarrelBundle.app");
        
        // Now decompress the downloaded engine and included libs in the Frameworks folder
        // Set the target path URL
        let frameworksURL = NSBundle(URL: newBundleURL)!.privateFrameworksURL;
        
        // Let's setup a new thread
        let asyncThread:dispatch_queue_t = dispatch_queue_create("uk.co.barrelapp.decompress", DISPATCH_QUEUE_SERIAL);
        dispatch_async(asyncThread, {() in
            self.currentStageName = "Extracting Engine archive..."
            self.currentImportIsIndeterminate = false;
            self.currentImportAnimate = false;
            if let dEngine = self.downloadedEngine {
                var sourcePath:String = dEngine.path!
                var destinationPath:String = frameworksURL!.path!
                SSZipArchive.unzipFileAtPath(sourcePath, toDestination: destinationPath, delegate: self);
            }
        });
    }
    
    func zipArchiveProgressEvent(loaded: Int, total: Int) {
        self.currentImportMax = Int64(total);
        self.currentImportValue = Int64(loaded);
    }
    
    func zipArchiveDidUnzipArchiveAtPath(path: String!, zipInfo: unz_global_info, unzippedPath: String!) {
        NSLog("Done!");
        // Now, on the unzipped path we should have the libraries archive.
        // Decompress it on the spot, then delete the .zip
        // Which file did we just extract? If it was the main engine bundle, proceed with the libraries
        if (path.lastPathComponent == self.downloadedEngine!.lastPathComponent!) {
            self.currentStageName = "Extracting Libraries archive..."
            let librariesURL:NSURL = NSURL(fileURLWithPath: unzippedPath)!.URLByAppendingPathComponent("libraries.zip");
            let destinationURL:NSURL = NSURL(fileURLWithPath: unzippedPath)!
            SSZipArchive.unzipFileAtPath(librariesURL.path!, toDestination: destinationURL.path!, delegate: self);
        }
        else if (path.lastPathComponent == "libraries.zip") {
            // Good to proceed with initialising Wine
            // First, delete the libraries
            var tempDirURL:NSURL = AppDelegate.preferredGamesFolderURL().URLByAppendingPathComponent(".tmp", isDirectory: true);
            let newBundlePath:String = "\(tempDirURL.path!)/BarrelBundle.app";
            NSFileManager.defaultManager().removeItemAtURL(NSURL(fileURLWithPath: path)!, error: nil);
            var taskManager:BLTaskManager = BLTaskManager();
            taskManager.didFinishCommandSelector = "didFinishInitPrefixCommand:";
            taskManager.startTaskWithCommand(newBundlePath, arguments: [ "--initPrefix" ], observer: self);
        }
        else {
            // What the hell just happened?
        }
    }
    
    func didFinishInitPrefixCommand(notification:NSNotification) {
        NSLog("finished???");
    }
}