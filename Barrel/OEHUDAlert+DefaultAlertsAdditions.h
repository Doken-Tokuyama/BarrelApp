/*
 Copyright (c) 2012, OpenEmu Team
 
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


#import "OEHUDAlert.h"

extern NSString *const OEMaxSaveGameNameLengthKey;

@interface OEHUDAlert (DefaultAlertsAdditions)

+ (id)quitApplicationAlert;
+ (id)saveGameAlertWithProposedName:(NSString *)name;
+ (id)saveAutoSaveGameAlert;
+ (id)loadAutoSaveGameAlert;
+ (id)deleteStateAlertWithStateName:(NSString *)stateName;
+ (id)resetSystemAlert;
+ (id)stopEmulationAlert;

+ (id)removeGamesFromCollectionAlert;
+ (id)removeGamesFromLibraryAlert:(BOOL)multipleGames;
+ (id)removeGameFilesFromLibraryAlert:(BOOL)multipleGames;

+ (id)showProgressAlertWithMessage:(NSString *)message andTitle:(NSString *)title indeterminate:(BOOL)indeterminate;
+ (id)showManualImportAlertWithVolumeName:(NSString *)volumeName andPopupItems:(NSMutableArray *)items;
+ (id)showGenreSelectionAlertWithGenres:(NSArray *)genres;

+ (id)alertWithMessageText:(NSString *)msgText defaultButton:(NSString *)defaultButtonLabel alternateButton:(NSString *)alternateButtonLabel otherButton:(NSString *)otherButton;
+ (id)manualGameSearchWithVolumeName:(NSString *)gameName;
+ (id)alertWithMessageAndInputbox:(NSString *)message;

@end
