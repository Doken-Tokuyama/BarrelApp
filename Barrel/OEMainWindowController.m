/*
 Copyright (c) 2011, OpenEmu Team
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
     * Redistributions of source code must retain the above copyright
       notice, this list of conditions and the following disclaimer.
     * Redistributions in binary form must reproduce the above copyright
       notice, this list of conditions and the following disclaimer in the
       documentation and/or other materials provided with the distribution.
     * Neither the name of the OpenEmu Team nor the
       names of its contributors may be used to endorse or promote products
       derived from this software without specific prior written permission.
 
 THIS SOFTWARE IS PROVIDED BY OpenEmu Team ''AS IS'' AND ANY
 EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL OpenEmu Team BE LIABLE FOR ANY
 DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "OEMainWindowController.h"
#import "OEMainWindowContentController.h"

#import "NSImage+OEDrawingAdditions.h"
#import "OEMainWindow.h"
#import "NSWindow+OEFullScreenAdditions.h"
#import "OECoreUpdater.h"
#import "OELibraryController.h"

#import "NSViewController+OEAdditions.h"
#import "OEGameCoreManager.h"

#import "OEHUDAlert+DefaultAlertsAdditions.h"
#import "OEDBGame.h"

#import "NSView+FadeImage.h"
#import "OEFadeView.h"

NSString *const OEForcePopoutGameWindowKey = @"forcePopout";
NSString *const OEFullScreenGameWindowKey  = @"fullScreen";
NSString *const OEMainWindowFullscreenKey  = @"mainWindowFullScreen";

#define MainMenu_Window_OpenEmuTag 501
@interface OEMainWindowController () <OELibraryControllerDelegate> {
    OEGameDocument *_gameDocument;
    BOOL            _shouldExitFullScreenWhenGameFinishes;
    BOOL            _shouldUndockGameWindowOnFullScreenExit;
    BOOL            _resumePlayingAfterFullScreenTransition;
}
- (void)OE_replaceCurrentContentController:(NSViewController *)oldController withViewController:(NSViewController *)newController;
- (void)OE_gameDidFinishEmulating:(id)sender;
@end

@implementation OEMainWindowController
@synthesize currentContentController;
@synthesize defaultContentController;
@synthesize allowWindowResizing;
@synthesize gamesRunning;
@synthesize mainWindowRunsGame;
@synthesize libraryController;
@synthesize placeholderView;

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    currentContentController = nil;
    [self setDefaultContentController:nil];
    [self setLibraryController:nil];
    [self setPlaceholderView:nil];
}

- (id)initWithWindow:(NSWindow *)window
{
    self = [super initWithWindow:window];
    if(!self) return nil;
    
    // Since restoration from autosave happens before NSWindowController
    // receives -windowDidLoad and we are autosaving the window size, we
    // need to set allowWindowResizing to YES before -windowDidLoad
    allowWindowResizing = YES;
    gamesRunning = 0;
    mainWindowRunsGame = NO;
    _shouldUndockGameWindowOnFullScreenExit = NO;
    
    return self;
}

- (void)windowDidLoad
{
    NSWindow *window = [self window];
    
    [super windowDidLoad];
    
    [[self libraryController] setDelegate:self];
    
    [window setWindowController:self];
    [window setDelegate:self];
    
    // Setup Window behavior
    [window setRestorable:NO];
    [window setExcludedFromWindowsMenu:YES];
    
    
    [self setCurrentContentController:[self libraryController] animate:NO];
    
#if DEBUG_PRINT
    [window setTitle:[[window title] stringByAppendingString:@" (DEBUG BUILD)"]];
#endif
}

- (NSString *)windowNibName
{
    return @"MainWindow";
}

- (void)openGameDocument:(OEGameDocument *)aDocument;
{
    NSUserDefaults *standardDefaults = [NSUserDefaults standardUserDefaults];
    BOOL forcePopout = [standardDefaults boolForKey:OEForcePopoutGameWindowKey];
    BOOL fullScreen  = [standardDefaults boolForKey:OEFullScreenGameWindowKey];
    
    _shouldExitFullScreenWhenGameFinishes = NO;

    gamesRunning += 1;

    if(forcePopout)
    {
    }
    else
    {
        _shouldExitFullScreenWhenGameFinishes = ![[self window] isFullScreen];
        _gameDocument = aDocument;
        mainWindowRunsGame = YES;

        if(fullScreen && ![[self window] isFullScreen])
        {
            [NSApp activateIgnoringOtherApps:YES];
            
            [self OE_replaceCurrentContentController:[self currentContentController] withViewController:nil];
            [[self window] toggleFullScreen:self];
        }
        else
        {
        }
    }
}


#pragma mark -
- (void)OE_replaceCurrentContentController:(NSViewController *)oldController withViewController:(NSViewController *)newController
{
    NSView *contentView = [self placeholderView];
    
    // final target
    [[newController view] setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [[newController view] setFrame:[contentView frame]];
    
    [oldController viewWillDisappear];
    [newController viewWillAppear];
    
    if(oldController != nil)
    {
        if(newController != nil)
        {
            [contentView replaceSubview:[oldController view] with:[newController view]];
        }
        else
        {
            [[oldController view] removeFromSuperview];
        }
    }
    else
    {
        if(newController != nil)
        {
            [contentView addSubview:[newController view]];
        }
    }
    
    [oldController viewDidDisappear];
    [newController viewDidAppear];
    
    if(newController)
    {
        [[self window] makeFirstResponder:[newController view]];
    }
    
    currentContentController = newController;
}

- (void)setCurrentContentController:(NSViewController *)controller animate:(BOOL)shouldAnimate
{
    if(controller == nil) controller = [self libraryController];
    
    if(controller == [self currentContentController]) return;

    NSView *placeHolderView = [self placeholderView];

    // We use Objective-C blocks to factor out common code used in both animated and non-animated controller switching
    void (^sendViewWillDisappear)(void) = ^{
        [currentContentController viewWillDisappear];
        [controller viewWillAppear];
    };

    void (^replaceController)(NSView *) =
    ^(NSView *viewToReplace){
        [[controller view] setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        [[controller view] setFrame:[placeHolderView frame]];

        if (viewToReplace)
            [placeHolderView replaceSubview:viewToReplace with:[controller view]];
        else
            [placeHolderView addSubview:[controller view]];
        
        [[self window] makeFirstResponder:[controller view]];

        [currentContentController viewDidDisappear];
        [controller viewDidAppear];
        currentContentController = controller;

        [viewToReplace removeFromSuperview];
    };

    if(shouldAnimate)
    {
        NSBitmapImageRep *currentState = [[self placeholderView] fadeImage], *newState = nil;
        if([currentContentController respondsToSelector:@selector(setCachedSnapshot:)])
            [(id <OEMainWindowContentController>)currentContentController setCachedSnapshot:currentState];

        sendViewWillDisappear();

        OEFadeView *fadeView = [[OEFadeView alloc] initWithFrame:[placeHolderView bounds]];

        if(currentContentController)
            [placeholderView replaceSubview:[currentContentController view] with:fadeView];
        else
            [placeholderView addSubview:fadeView];

        if([controller respondsToSelector:@selector(cachedSnapshot)])
            newState = [(id <OEMainWindowContentController>)controller cachedSnapshot];

        [fadeView fadeFromImage:currentState toImage:newState callback:^{
            replaceController(fadeView);
         }];
    }
    else
    {
        sendViewWillDisappear();
        replaceController([currentContentController view]);
    }
}

- (void)setCurrentContentController:(NSViewController *)newCurrentContentController
{
    [self setCurrentContentController:newCurrentContentController animate:YES];
}

- (IBAction)undockGameWindow:(id)sender
{
    mainWindowRunsGame = NO;

    if(_shouldExitFullScreenWhenGameFinishes && [[self window] isFullScreen])
    {
        [[self window] toggleFullScreen:self];
        _shouldExitFullScreenWhenGameFinishes = NO;
        _shouldUndockGameWindowOnFullScreenExit = YES;
    }
    else
    {
        [self OE_replaceCurrentContentController:[self currentContentController] withViewController:nil];
        [self setCurrentContentController:nil];
        _gameDocument = nil;
    }
}

- (void)OE_gameDidFinishEmulating:(id)sender
{
    gamesRunning -= 1;
}

#pragma mark -
#pragma mark OELibraryControllerDelegate protocol conformance
- (void)libraryController:(OELibraryController *)sender didSelectGame:(OEDBGame *)aGame
{
    // Get the game's path from the managed object
    NSString *bundlePath = [aGame bundlePath];
    if ([bundlePath length] > 0) {
        // Check if the file still exists in that path
        if ([[NSFileManager defaultManager] fileExistsAtPath:bundlePath]) {
            // Launch the game
            [self runScript:bundlePath withArguments:nil shouldWaitForProcess:NO];
        }
    }
}

- (void)libraryController:(OELibraryController *)sender didSelectGameWineCfg:(OEDBGame *)aGame
{
    // Get the game's path from the managed object
    NSString *bundlePath = [aGame bundlePath];
    if ([bundlePath length] > 0) {
        // Check if the file still exists in that path
        if ([[NSFileManager defaultManager] fileExistsAtPath:bundlePath]) {
            // Launch the game
            [self runScript:bundlePath withArguments:[NSArray arrayWithObjects:@"--runWineCfg", nil] shouldWaitForProcess:NO];
        }
    }
}

- (void)libraryController:(OELibraryController *)sender didSelectGameRegedit:(OEDBGame *)aGame {
    // Get the game's path from the managed object
    NSString *bundlePath = [aGame bundlePath];
    if ([bundlePath length] > 0) {
        // Check if the file still exists in that path
        if ([[NSFileManager defaultManager] fileExistsAtPath:bundlePath]) {
            // Launch the game
            [self runScript:bundlePath withArguments:[NSArray arrayWithObjects:@"--run", [NSString stringWithFormat:@"%@/Contents/Resources/drive_c/windows/regedit.exe", bundlePath], nil] shouldWaitForProcess:NO];
        }
    }
}

- (void)runScript:(NSString*)scriptName withArguments:(NSArray *)arguments shouldWaitForProcess:(BOOL)waitForProcess
{
    NSTask *task;
    task = [[NSTask alloc] init];
    
    NSBundle *barrelAppBundle = [NSBundle bundleWithPath:scriptName];
    NSArray *argumentsArray;
    [task setLaunchPath: [barrelAppBundle executablePath]];
    
    if (arguments) {
        argumentsArray = arguments;
        [task setArguments: argumentsArray];
    }
    
    NSPipe *pipe;
    pipe = [NSPipe pipe];
    [task setStandardOutput: pipe];
    
    NSFileHandle *file;
    file = [pipe fileHandleForReading];
    
    [[NSApplication sharedApplication] deactivate]; // Send Barrel to the back
    [task launch];
    
    if (waitForProcess) {
        NSData *data;
        data = [file readDataToEndOfFile];
        
        NSString *string;
        string = [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding];
    }
}

- (void)libraryController:(OELibraryController *)sender didSelectSaveState:(OEDBSaveState *)aSaveState
{
}

#pragma mark - OEGameViewControllerDelegate protocol conformance
- (void)emulationDidFinishForGameViewController:(id)sender
{
    if(_shouldExitFullScreenWhenGameFinishes && [[self window] isFullScreen])
    {
        [[self window] toggleFullScreen:self];
        _shouldExitFullScreenWhenGameFinishes = NO;
    }
}

#pragma mark -
#pragma mark NSWindow delegate
- (NSSize)windowWillResize:(NSWindow *)sender toSize:(NSSize)frameSize
{
    return [self allowWindowResizing] ? frameSize : [sender frame].size;
}

- (BOOL)windowShouldClose:(id)sender
{
    if([self currentContentController] == [self libraryController])
        return YES;
    else
    {
        return NO;
    }
}

- (void)windowWillClose:(NSNotification *)notification
{
    // Make sure the current content controller gets viewWillDisappear / viewDidAppear so it has a chance to store its state
    if([self currentContentController] == [self libraryController])
    {
        [[self libraryController] viewWillDisappear];
        [[self libraryController] viewDidDisappear];
        [[self libraryController] viewWillAppear];
        [[self libraryController] viewDidAppear];
    }
    
    [self setCurrentContentController:nil];
}


- (void)windowDidBecomeMain:(NSNotification *)notification
{
    NSMenu *mainMenu = [NSApp mainMenu];
    
    NSMenu *windowMenu = [[mainMenu itemAtIndex:5] submenu];
    NSMenuItem *item = [windowMenu itemWithTag:MainMenu_Window_OpenEmuTag];
    [item setState:NSOnState];
}

- (void)windowDidResignMain:(NSNotification *)notification
{
    NSMenu *mainMenu = [NSApp mainMenu];
    
    NSMenu *windowMenu = [[mainMenu itemAtIndex:5] submenu];
    NSMenuItem *item = [windowMenu itemWithTag:MainMenu_Window_OpenEmuTag];
    [item setState:NSOffState];
}

- (void)windowWillEnterFullScreen:(NSNotification *)notification
{
    if(_gameDocument)
    {
    }
}

- (void)windowDidEnterFullScreen:(NSNotification *)notification
{
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:OEMainWindowFullscreenKey];
    if(_gameDocument)
    {
    }
}

- (void)windowWillExitFullScreen:(NSNotification *)notification
{
    if(_gameDocument)
    {
    }
}

- (void)windowDidExitFullScreen:(NSNotification *)notification
{
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:OEMainWindowFullscreenKey];

    if(_shouldUndockGameWindowOnFullScreenExit)
    {
        _shouldUndockGameWindowOnFullScreenExit = NO;
        
        [self OE_replaceCurrentContentController:[self currentContentController] withViewController:nil];
        [self setCurrentContentController:nil];

        _gameDocument = nil;
    }
    else if(_gameDocument)
    {
    }
}

#pragma mark -
#pragma mark Menu Items

- (IBAction)launchLastPlayedROM:(id)sender
{
}

@end
