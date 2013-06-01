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

#import "BarrelWineLauncher.h"

@implementation BarrelWineLauncher

-(id) initWithArguments:(NSMutableArray *)arguments {
    // [NSThread sleepForTimeInterval:10.0f];
    if (self = [super init]) {
        [self setArguments:arguments];
        [self setExecutablePath:[[NSBundle mainBundle] executablePath]];
        [self setFrameworksPath:[NSString stringWithFormat:@"%@/Contents/Frameworks", [[NSBundle mainBundle] bundlePath]]];
        [self setWineBundlePath:[NSString stringWithFormat:@"%@/blwine.bundle", [self frameworksPath]]];
        [self setWinePrefixPath:[[NSBundle mainBundle] resourcePath]];
    }
    
    return self;
}

-(void) runWine {
    if ([(NSString *)[[self arguments] objectAtIndex:1]isEqualToString:@"initPrefix"]) {
        [self initWinePrefix];
    }
}

-(void) initWinePrefix {
    NSString *script = [NSString stringWithFormat:@"export PATH=\"%@/bin:%@/bin:$PATH:/opt/local/bin:/opt/local/sbin\";export WINEPREFIX=\"%@\";DYLD_FALLBACK_LIBRARY_PATH=\"%@\" wineboot --init", [self wineBundlePath], [self frameworksPath], [self winePrefixPath], [self frameworksPath]];
    [self setScriptPath:@""];
    // [self runScript:script withArguments:@"" withPath:NO];
    [self systemCommand:script];
}

- (NSString *)systemCommand:(NSString *)command
{
	FILE *fp;
	char buff[512];
	NSMutableString *returnString = [[NSMutableString alloc] init];
	fp = popen([command cStringUsingEncoding:NSUTF8StringEncoding], "r");
	while (fgets( buff, sizeof buff, fp))
    {
        [returnString appendString:[NSString stringWithCString:buff encoding:NSUTF8StringEncoding]];
    }
	pclose(fp);
	//cut out trailing new line
	if ([returnString hasSuffix:@"\n"])
    {
        [returnString deleteCharactersInRange:NSMakeRange([returnString length]-1,1)];
    }
	return [NSString stringWithString:returnString];
}

-(void) runScript:(NSString*)scriptName withArguments:(NSString *)arguments withPath:(BOOL)hasPath
{
    NSTask *task;
    task = [[NSTask alloc] init];
    
    NSArray *argumentsArray;
    if (hasPath) {
        NSString* newpath = [NSString stringWithFormat:@"%@/%@",[self scriptPath], scriptName];
        [task setLaunchPath: newpath];
    }
    else {
        [task setLaunchPath: scriptName];
    }
    argumentsArray = [NSArray arrayWithObjects:arguments, nil];
    [task setArguments: argumentsArray];
    
    NSPipe *pipe;
    pipe = [NSPipe pipe];
    [task setStandardOutput: pipe];
    
    NSFileHandle *file;
    file = [pipe fileHandleForReading];
    
    [task launch];
}

@end