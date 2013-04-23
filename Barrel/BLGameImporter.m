/*
 Copyright (c) 2013, Barrel Team
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
 * Redistributions of source code must retain the above copyright
 notice, this list of conditions and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright
 notice, this list of conditions and the following disclaimer in the
 documentation and/or other materials provided with the distribution.
 * Neither the name of the Barrel Team nor the
 names of its contributors may be used to endorse or promote products
 derived from this software without specific prior written permission.
 
 THIS SOFTWARE IS PROVIDED BY Barrel Team ''AS IS'' AND ANY
 EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL Barrel Team BE LIABLE FOR ANY
 DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "BLGameImporter.h"
#import "BLImportItem.h"

#import "NSArray+OEAdditions.h"

static const int MaxSimultaneousImports = 1; // imports can't really be simultaneous because access to queue is not ready for multithreadding right now

NSString *const BLImportInfoSystemID        = @"systemID";
NSString *const BLImportInfoCollectionID    = @"collectionID";

@interface BLGameImporter ()
{
    dispatch_queue_t dispatchQueue;
}

@property(readwrite)            NSInteger          status;
@property(readwrite)            NSInteger          activeImports;
@property(readwrite)            NSInteger          numberOfProcessedItems;
@property(readwrite, nonatomic) NSInteger          totalNumberOfItems;
@property(readwrite)            NSMutableArray    *queue;
@property(weak)                 OELibraryDatabase *database;

- (void)processNextItemIfNeeded;

@end

@implementation BLGameImporter
@synthesize database, delegate;

+ (void)initialize
{
    if (self != [BLGameImporter class]) return;
    [[NSUserDefaults standardUserDefaults] registerDefaults:(@{
                                                             OEOrganizeLibraryKey: @(YES),
                                                             OECopyToLibraryKey: @(YES),OEAutomaticallyGetInfoKey: @(YES),
                                                             })];
}

- (id)initWithDatabase:(OELibraryDatabase *)aDatabase
{
    self = [super init];
    if (self) {
        [self setDatabase:aDatabase];
        [self setQueue:[NSMutableArray array]];
        
        dispatchQueue = dispatch_queue_create("com.appcake.importqueue", DISPATCH_QUEUE_SERIAL);
        dispatch_queue_t priority = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0);
        dispatch_set_target_queue(dispatchQueue, priority);
        [self setStatus:BLImporterStatusStopped];
    }
    return self;
}

- (void)processNextItemIfNeeded
{
    IMPORTDLog(@"%s && %s -> -processNextItem", BOOL_STR([self status] == BLImporterStatusRunning), BOOL_STR([self activeImports] < MaxSimultaneousImports));
    if ([self status] == BLImporterStatusRunning && [self activeImports] < MaxSimultaneousImports)
    {
        [self processNextItem];
    }
}

- (void)processNextItem
{
    self.activeImports++;
    IMPORTDLog(@"activeImports: %ld", self.activeImports);
    
    BLImportItem *nextItem = [[self queue] firstObjectMatchingBlock:^BOOL (id evaluatedObject)
                             {
                                 return [evaluatedObject importState] == BLImportItemStatusIdle;
                             }];
    if (nextItem != nil)
    {
        [nextItem setImportState:BLImportItemStatusActive];
        dispatch_async(dispatchQueue, ^{
            importBlock(self, nextItem);
        });
        
        if (MaxSimultaneousImports > 1) dispatch_async(dispatchQueue, ^{
            [self processNextItemIfNeeded];
        });
    }
    else
    {
        self.activeImports--;
        if ([self numberOfProcessedItems] == [self totalNumberOfItems])
        {
            dispatch_async(dispatchQueue, ^{
                if ([[self queue] count] == 0)
                {
                    [self setQueue:[NSMutableArray array]];
                    [self setNumberOfProcessedItems:0];
                    
                    [self setStatus:BLImporterStatusStopped];
                }
                else
                    [self processNextItemIfNeeded];
            });
        }
    }
}

- (void)dealloc
{
    dispatch_release(dispatchQueue);
}

#pragma mark - Import Block
static void importBlock(BLGameImporter *importer, BLImportItem *item)
{
    @autoreleasepool {
        IMPORTDLog(@"Status: %ld | Step: %d | URL: %@", [importer status], [item importStep], [item sourceURL]);
        if ([importer status] == BLImporterStatusPausing || [importer status] == BLImporterStatusPaused)
        {
            DLog(@"skipping item!");
            importer.activeImports--;
            if ([item importState] == BLImportItemStatusActive)
                [item setImportState:BLImportItemStatusIdle];
        }
        else if ([importer status] == BLImporterStatusStopping || [importer status] == BLImporterStatusStopping)
        {
            
        }
    }
}

#pragma mark - Importing games into collections
- (BOOL)importItemAtPath:(NSString *)path intoCollectionWithID:(NSURL *)collectionID
{
    return [self importItemAtPath:path intoCollectionWithID:collectionID withCompletionHandler:nil];
}

#pragma mark - Importing games into collections with completion handler
- (BOOL)importItemAtPath:(NSString *)path intoCollectionWithID:(NSURL *)collectionID withCompletionHandler:(BLImportItemCompletionBlock)handler
{
    NSURL *url = [NSURL fileURLWithPath:path];
    return [self importItemAtURL:url intoCollectionWithID:collectionID withCompletionHandler:handler];
}

- (BOOL)importItemAtURL:(NSURL *)url intoCollectionWithID:(NSURL *)collectionID withCompletionHandler:(BLImportItemCompletionBlock)handler
{
    id item = [[self queue] firstObjectMatchingBlock:
               ^ BOOL (id item)
               {
                   return [[item URL] isEqualTo:url];
               }];
    
    if (item == nil) {
        BLImportItem *item = [BLImportItem itemWithURL:url andCompletionHandler:handler];
        if (item)
        {
            if (collectionID) [[item importInfo] setObject:collectionID forKey:BLImportInfoCollectionID];
            [[self queue] addObject:item];
            [self start];
            return YES;
        }
    }
    
    return NO;
}

#pragma mark - Controlling Import -
- (void)start
{
    IMPORTDLog();
    if ([self status] == BLImporterStatusPaused || [self status] == BLImporterStatusStopped)
    {
        [self setStatus:BLImporterStatusRunning];
        [self processNextItemIfNeeded];
        // Perform selector here
    }
}

@end
