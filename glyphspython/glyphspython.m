//
//  glyphspython.m
//  glyphspython
//
//  Created by tfuji on 06/10/2016.
//  Copyright © 2016 Morisawa Inc. All rights reserved.
//

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <libgen.h>
#include <string.h>
#include <sys/syslimits.h>
#include <sys/types.h>
#include <sys/wait.h>

#include <dlfcn.h>
#include <libproc.h>

#import <Foundation/Foundation.h>
#import <ApplicationServices/ApplicationServices.h>
#import <Python/Python.h>

#import <AppKit/AppKit.h>
#import <objc/runtime.h>

const CFStringRef kGlyphsAppIdentifier = CFSTR("com.GeorgSeifert.Glyphs2");
NSString * const GlyphsAppIdentifier = (__bridge NSString *)kGlyphsAppIdentifier;

@protocol GlyphsPlugin <NSObject>
@property(readonly, nonatomic) unsigned long long interfaceVersion;
- (void)loadPlugin;
@end

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (nonatomic, readonly) NSArray<NSBundle *> *filterBundles;
@property (nonatomic, readonly) NSArray<NSBundle *> *fileFormatBundles;
@property (nonatomic, readonly) NSArray<NSBundle *> *paletteBundles;
@property (nonatomic, readonly) NSArray<NSBundle *> *customPluginBundles;
@property (nonatomic, readonly) NSArray<id<GlyphsPlugin>> *filterInstances;
@property (nonatomic, readonly) NSArray<id<GlyphsPlugin>> *fileFormatInstances;
@end

@implementation AppDelegate

- (instancetype)init {
    if ((self = [super init])) {
        [self registerDefaults];
    }
    return self;
}

- (void)forwardInvocation:(NSInvocation *)invocation {
    if ([self respondsToSelector:[invocation selector]]) {
        [super forwardInvocation:invocation];
    }
}
    
- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector {
    NSMethodSignature *signature = [super methodSignatureForSelector:selector];
    if (!signature) {
        signature = [NSMethodSignature signatureWithObjCTypes:"v@:"];
    }
    return signature;
}

- (void)registerDefaults {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        @"GSFontViewWidth": @(8500),
        @"scale": @(0.5),
        @"showMetrics": @(YES),
        @"showHints": @(YES),
        @"showNodes": @(YES),
        @"showInfo": @(YES),
        @"OffsettedMasterCompatibility": @(YES),
        @"fillPreview": @(YES),
        @"showBackground": @(YES),
        @"showShadowPath": @(YES),
        @"drawShadowAccents": @(YES),
        @"selected Tool": @(2),
        @"glyphIconCollectionSize": @(128.0),
        @"SUShowCuttingEdgeVersion": @(NO),
        @"macroCode": @"# type your Python code here and press cmd+Return to run.",
        @"ImportConvertReadableGlyphnames": @(YES),
        @"ImportKeepGlyphsNames": @(YES),
        @"GSDisableVersionsinLion": @(YES),
        @"supportsSmartGlyphs": @(YES),
        @"showBoundingBox": @(YES)
    }];
}

- (void)_loadAllPlugins {
    NSMutableArray *mutableBundles = [[NSMutableArray alloc] initWithCapacity:0];
    NSMutableArray *mutableInstances = [[NSMutableArray alloc] initWithCapacity:0];
    [mutableBundles addObjectsFromArray:[self _loadPluginsFromDirectoryAtPath:[[NSBundle mainBundle] builtInPlugInsPath]]];
    [mutableBundles addObjectsFromArray:[self _loadPluginsFromDirectoryAtPath:[[[NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject] stringByAppendingPathComponent:@"Glyphs"] stringByAppendingPathComponent:@"Plugins"]]];
    for (NSBundle *bundle in mutableBundles) {
        id<GlyphsPlugin> instance = [[[bundle principalClass] alloc] init];
        if (instance) {
            if ([instance respondsToSelector:@selector(loadPlugin)]) [instance loadPlugin];
            [mutableInstances addObject:instance];
        }
    }
    _filterBundles = [mutableBundles filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
        return [[(NSBundle *)evaluatedObject principalClass] conformsToProtocol:NSProtocolFromString(@"GlyphsFilter")];
    }]];
    _fileFormatBundles = [mutableBundles filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
        return [[(NSBundle *)evaluatedObject principalClass] conformsToProtocol:NSProtocolFromString(@"GlyphsFileFormat")];
    }]];
    _filterInstances = [mutableInstances filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
        return [evaluatedObject conformsToProtocol:NSProtocolFromString(@"GlyphsFilter")];
    }]];
    _fileFormatInstances = [mutableInstances filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
        return [evaluatedObject conformsToProtocol:NSProtocolFromString(@"GlyphsFileFormat")];
    }]];
}

- (NSArray<NSBundle *> *)_loadPluginsFromDirectoryAtPath:(NSString *)aPath {
    NSSet *validPluginExtensions = [NSSet setWithArray:@[@"glyphsFilter", @"glyphsFileFormat"]];
    NSMutableArray *mutableBundles = [[NSMutableArray alloc] initWithCapacity:0];
    for (NSString *filename in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:aPath error:nil]) {
        NSString *extension = [filename pathExtension];
        if ([validPluginExtensions containsObject:extension]) {
            NSBundle *bundle = [NSBundle bundleWithPath:[aPath stringByAppendingPathComponent:filename]];
            if (bundle) {
                // Note that - [NSBundle principalClass] has a side effect to cause a code loading.
                if ([bundle principalClass] && [bundle isLoaded]) {
                    [mutableBundles addObject:bundle];
                }
            }
        }
    }
    return [mutableBundles copy];
}

@end

@implementation NSApplication (GSApplicationAdditions)

+ (void)load {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class class = object_getClass(self);
        SEL originalSelector = @selector(sharedApplication);
        SEL swizzledSelector = @selector(_sharedApplication);
        Method originalMethod = class_getClassMethod(class, originalSelector);
        Method swizzledMethod = class_getClassMethod(class, swizzledSelector);
        BOOL didAddMethod = class_addMethod(class, originalSelector, method_getImplementation(swizzledMethod), method_getTypeEncoding(swizzledMethod));
        if (didAddMethod) {
            class_replaceMethod(class, swizzledSelector, method_getImplementation(originalMethod), method_getTypeEncoding(originalMethod));
        } else {
            method_exchangeImplementations(originalMethod, swizzledMethod);
        }
    });
}

+ (NSApplication *)_sharedApplication {
    // A dirty hack to replace the global 'Glyphs' object with GSApplication instead of NSApplication.
    static dispatch_once_t once;
    static NSApplication *sharedInstance = nil;
    static AppDelegate *delegate = nil;
    dispatch_once(&once, ^{
        delegate = [[AppDelegate alloc] init];
        sharedInstance = [[NSClassFromString(@"GSApplication") alloc] init];
        [sharedInstance setDelegate:delegate];
    });
    return sharedInstance;
}

@end

@implementation NSWindowController (NSWindowControllerAdditions)
    
+ (void)load {
    // Swizzle - showWindow: with the empty implementation to maintain its headless behaviour.
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class class = [self class];
        SEL originalSelector = @selector(showWindow:);
        SEL swizzledSelector = @selector(_showWindow:);
        Method originalMethod = class_getInstanceMethod(class, originalSelector);
        Method swizzledMethod = class_getInstanceMethod(class, swizzledSelector);
        BOOL didAddMethod = class_addMethod(class, originalSelector, method_getImplementation(swizzledMethod), method_getTypeEncoding(swizzledMethod));
        if (didAddMethod) {
            class_replaceMethod(class, swizzledSelector, method_getImplementation(originalMethod), method_getTypeEncoding(originalMethod));
        } else {
            method_exchangeImplementations(originalMethod, swizzledMethod);
        }
    });
}
    
- (void)_showWindow:(id)sender {
    return;
}
    
@end


@implementation NSProcessInfo (NSProcessInfoAdditions)
    
+ (void)load {
    // Swizzle - arguments to pretend as if it's launched from the bundle.
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class class = [self class];
        SEL originalSelector = @selector(arguments);
        SEL swizzledSelector = @selector(_arguments);
        Method originalMethod = class_getInstanceMethod(class, originalSelector);
        Method swizzledMethod = class_getInstanceMethod(class, swizzledSelector);
        BOOL didAddMethod = class_addMethod(class, originalSelector, method_getImplementation(swizzledMethod), method_getTypeEncoding(swizzledMethod));
        if (didAddMethod) {
            class_replaceMethod(class, swizzledSelector, method_getImplementation(originalMethod), method_getTypeEncoding(originalMethod));
        } else {
            method_exchangeImplementations(originalMethod, swizzledMethod);
        }
    });
}
    
- (NSArray<NSString *> *)_arguments {
    return @[[[NSBundle mainBundle] executablePath]];
}
    
@end

@implementation NSUserDefaults (NSUserDefaultsAdditions)
    
+ (void)load {
    // Swizzle + standardUserDefault: with our custom implementation.
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class class = object_getClass(self);
        SEL originalSelector = @selector(standardUserDefaults);
        SEL swizzledSelector = @selector(_standardUserDefaults);
        Method originalMethod = class_getClassMethod(class, originalSelector);
        Method swizzledMethod = class_getClassMethod(class, swizzledSelector);
        BOOL didAddMethod = class_addMethod(class, originalSelector, method_getImplementation(swizzledMethod), method_getTypeEncoding(swizzledMethod));
        if (didAddMethod) {
            class_replaceMethod(class, swizzledSelector, method_getImplementation(originalMethod), method_getTypeEncoding(originalMethod));
        } else {
            method_exchangeImplementations(originalMethod, swizzledMethod);
        }
    });
}
    
+ (id)_standardUserDefaults {
    // Here we explicitly set the application identifier via ivar so that it should be passed to CFPreference functions.
    NSUserDefaults *userDefaults = [[self class] _standardUserDefaults];
    Class class = object_getClass(userDefaults);
    Ivar identifier = class_getInstanceVariable(class, "_identifier_");
    object_setIvarWithStrongDefault(userDefaults, identifier, (__bridge id)kGlyphsAppIdentifier);
    return userDefaults;
}

@end

#pragma mark -

#import "mach_override.h"
#import <mach-o/dyld.h>

CFBundleRef GlyphsPythonMainBundle = NULL;
CFBundleRef (*origCFBundleGetMainBundle)(void);
CFBundleRef GlyphsPythonCFBundleGetMainBundle(void) {
    return GlyphsPythonMainBundle;
}

CFStringRef GlyphsPythonMainBundleExecutablePath = NULL;
int (*origNSGetExecutablePath)(char* buf, uint32_t* bufsize);
int GlyphsPythonNSGetExecutablePath(char* buf, uint32_t* bufsize) {
    return CFStringGetFileSystemRepresentation(GlyphsPythonMainBundleExecutablePath, buf, *bufsize) ? 0 : -1;
}

#pragma mark -

@protocol GSInstallPluginDocumentProtocol <NSObject>
- (id)initWithContentsOfURL:(NSURL *)URL ofType:(NSString *)type error:(NSError **)error;
@end

#pragma mark -

static int consume_register_license_option_if_available(int *argc, const char * argv[], NSString **path) {
    if (*argc >= 3) {
        if (strncmp(argv[1], "--register-license", strlen("--register-license")) == 0) {
            if (path) *path = [[[NSFileManager alloc] init] stringWithFileSystemRepresentation:argv[2] length:strlen(argv[2])];
            if (*argc > 3) memmove(&(argv[1]), &(argv[3]), *argc - 1 - 2);
            *argc = *argc - 2;
            return 1;
        }
    }
    return 0;
}

#pragma mark -

@interface GPInstalledApplication : NSObject <NSCopying>

@property (nonatomic, readonly) NSString *path;
@property (nonatomic, readonly) NSString *displayVersion;
@property (nonatomic, readonly) NSString *versionString;
@property (nonatomic, readonly) NSString *bundleIdentifier;

+ (NSArray<GPInstalledApplication *> *)applicationsWithBundleIdentifier:(NSString *)aBundleIdentifier;
+ (NSArray<GPInstalledApplication *> *)allGlyphsAppInstances;

- (instancetype)initWithPath:(NSString *)path displayVersion:(NSString *)displayVersion versionString:(NSString *)versionString bundleIdentifier:(NSString *)bundleIdentifier;

- (NSString *)fullVersionString;

@end

@implementation GPInstalledApplication

+ (NSArray<GPInstalledApplication *> *)applicationsWithBundleIdentifier:(NSString *)aBundleIdentifier {
    NSRegularExpression *separatorExpression = [NSRegularExpression regularExpressionWithPattern:@"^-{4,}$" options:0 error:nil];
    NSRegularExpression *pathExpression = [NSRegularExpression regularExpressionWithPattern:@"^\\s*path:\\s*(.*)$" options:0 error:nil];
    NSRegularExpression *displayVersionExpression = [NSRegularExpression regularExpressionWithPattern:@"^\\s*displayVersion:?\\s+(.*)$" options:0 error:nil];
    NSRegularExpression *versionStringExpression = [NSRegularExpression regularExpressionWithPattern:@"^\\s*versionString:\\s*(.*)$" options:0 error:nil];
    NSRegularExpression *bundleIdentifierExpression = [NSRegularExpression regularExpressionWithPattern:@"^\\s*identifier:\\s*(.*?)(?:\\s*\\(0x[0-9a-f]+\\))?$" options:0 error:nil];
    NSTask *task = [[NSTask alloc] init];
    if (@available(macOS 10.13, *)) {
        [task setExecutableURL:[NSURL fileURLWithPath:@"/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"]];
    } else {
        [task setLaunchPath:@"/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"];
    }
    [task setArguments:@[@"-dump"]];
    [task setStandardOutput:[NSPipe pipe]];
    [task launch];
    
    NSMutableArray <GPInstalledApplication *> *mutableApplications = [[NSMutableArray alloc] initWithCapacity:0];
    NSFileHandle *fileHandle = [[task standardOutput] fileHandleForReading];
    FILE *fp = fdopen([fileHandle fileDescriptor], "r");
    char *bytesForLine = NULL;
    size_t numberOfBytesForLine = 0;
    NSString *path = nil;
    NSString *displayVersion = nil;
    NSString *versionString = nil;
    NSString *bundleIdentifier = nil;
    while ((bytesForLine = fgetln(fp, &numberOfBytesForLine))) {
        NSTextCheckingResult *result = nil;
        NSString *lineString = [[NSString alloc] initWithBytesNoCopy:bytesForLine length:numberOfBytesForLine encoding:NSUTF8StringEncoding freeWhenDone:NO];
        if (lineString) {
            if ((result = [separatorExpression firstMatchInString:lineString options:0 range:NSMakeRange(0, [lineString length])])) {
                path = nil;
                displayVersion = nil;
                versionString = nil;
                bundleIdentifier = nil;
            } else if ((result = [pathExpression firstMatchInString:lineString options:0 range:NSMakeRange(0, [lineString length])])) {
                path = [lineString substringWithRange:[result rangeAtIndex:1]];
            } else if ((result = [displayVersionExpression firstMatchInString:lineString options:0 range:NSMakeRange(0, [lineString length])])) {
                displayVersion = [lineString substringWithRange:[result rangeAtIndex:1]];
            } else if ((result = [versionStringExpression firstMatchInString:lineString options:0 range:NSMakeRange(0, [lineString length])])) {
                versionString = [lineString substringWithRange:[result rangeAtIndex:1]];
            } else if ((result = [bundleIdentifierExpression firstMatchInString:lineString options:0 range:NSMakeRange(0, [lineString length])])) {
                bundleIdentifier = [lineString substringWithRange:[result rangeAtIndex:1]];
            }
            if (path && displayVersion && versionString && bundleIdentifier) {
                if ([bundleIdentifier isEqualToString:aBundleIdentifier]) {
                    [mutableApplications addObject:[[GPInstalledApplication alloc] initWithPath:path displayVersion:displayVersion versionString:versionString bundleIdentifier:bundleIdentifier]];
                }
                path = nil;
                displayVersion = nil;
                versionString = nil;
                bundleIdentifier = nil;
            }
        }
    }
    return [mutableApplications count] > 0 ? [mutableApplications copy] : nil;
}

+ (NSArray<GPInstalledApplication *> *)allGlyphsAppInstances {
    NSMutableDictionary<NSString *, GPInstalledApplication *> *mutableDictionary = [[NSMutableDictionary alloc] initWithCapacity:0];
    for (GPInstalledApplication *application in [GPInstalledApplication applicationsWithBundleIdentifier:GlyphsAppIdentifier]) {
        if ([[application path] hasPrefix:@"/"] && [[[[application path] pathComponents] objectAtIndex:1] isEqualToString:@"Applications"]) {
            if (![mutableDictionary objectForKey:[application fullVersionString]]) {
                [mutableDictionary setObject:application forKey:[application fullVersionString]];
            }
        }
    }
    return [[mutableDictionary allValues] sortedArrayUsingComparator:^NSComparisonResult(GPInstalledApplication *obj1, GPInstalledApplication *obj2) {
        NSComparisonResult result = [[obj1 fullVersionString] compare:[obj2 fullVersionString] options:NSNumericSearch];
        if (result == NSOrderedAscending) return NSOrderedDescending;
        if (result == NSOrderedDescending) return NSOrderedAscending;
        return result;
    }];
}

- (instancetype)initWithPath:(NSString *)path displayVersion:(NSString *)displayVersion versionString:(NSString *)versionString bundleIdentifier:(NSString *)bundleIdentifier {
    if ((self = [self init])) {
        _path = [path copy];
        _displayVersion = [displayVersion copy];
        _versionString = [versionString copy];
        _bundleIdentifier = [bundleIdentifier copy];
    }
    return self;
}

- (NSString *)fullVersionString {
    return [NSString stringWithFormat:@"%@ (%@)", _displayVersion, _versionString];
}

- (instancetype)copyWithZone:(NSZone *)zone {
    return self;
}

@end

static int list_installed_glyphs_versions(void) {
    BOOL hasInstalled = NO;
    for (GPInstalledApplication *application in [GPInstalledApplication allGlyphsAppInstances]) {
        fprintf(stdout, "%s\t%s\n", [[application fullVersionString] fileSystemRepresentation], [[application path] fileSystemRepresentation]);
        hasInstalled = YES;
    }
    return hasInstalled ? 0 : 1;
}

int main(int _argc, const char * _argv[]) {
    // Provide a Python interpreter with some modules loaded using C API.
    int result = 0;
    //
    int argc = _argc;
    const char **argv = _argv;
    //
    @autoreleasepool {
        // List installed glyphs versions if the '--list-verions' option is given.
        if (argc > 1 && strncmp(argv[1], "--list-versions", strlen("--list-versions")) == 0) {
            return list_installed_glyphs_versions();
        }
        // Find the appropriate bundle if the corresponding environment variable is given.
        NSString *pathForGlyphsApp = [[NSWorkspace sharedWorkspace] absolutePathForAppBundleWithIdentifier:GlyphsAppIdentifier];
        if (getenv("GLYPHSAPP_PATH")) {
            pathForGlyphsApp = [[NSString alloc] initWithCString:getenv("GLYPHSAPP_PATH") encoding:NSUTF8StringEncoding];
        }
        // Replace the exposed main bundle. As + [NSBundle mainBundle] calls CFBundleGetMainBundle() inside its implementation, the latter
        // Note that _NSGetExecutablePath() is also swizzled based on the assumption thCFPreferences resolves kCFPreferencesCurrentApplication based on
        // that value, but it doesn't seem to have any effects so far. Making sure to set up NSBundle/CFBundle/NSUserDefaults/CFPreferences is
        // especially important for Glyphs because it obtains the license information based on them and otherwise documents cannot be saved.
        // Note that mach_override is bundled with the project to override the builtin C functions.
        GlyphsPythonMainBundle = CFBundleCreate(NULL, (__bridge CFURLRef)[NSURL fileURLWithPath:pathForGlyphsApp]);
        CFURLRef URL = CFBundleCopyExecutableURL(GlyphsPythonMainBundle);
        CFStringRef percentEscapedPath = CFURLCopyPath(URL);
        GlyphsPythonMainBundleExecutablePath = CFURLCreateStringByReplacingPercentEscapesUsingEncoding(NULL, percentEscapedPath, CFSTR(""), kCFStringEncodingUTF8);
        CFRelease(percentEscapedPath);
        if (![(__bridge NSString *)GlyphsPythonMainBundleExecutablePath hasSuffix:@"Glyphs"]) {
            NSString *alternativeExecutablePath = [[(__bridge NSString *)GlyphsPythonMainBundleExecutablePath stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"Glyphs"];
            CFRelease(GlyphsPythonMainBundleExecutablePath);
            GlyphsPythonMainBundleExecutablePath = CFStringCreateCopy(NULL, (__bridge CFStringRef)alternativeExecutablePath);
        }
        mach_override_ptr((void *)CFBundleGetMainBundle, (void *)GlyphsPythonCFBundleGetMainBundle, (void **)&origCFBundleGetMainBundle);
        mach_override_ptr((void *)_NSGetExecutablePath, (void *)GlyphsPythonNSGetExecutablePath, (void **)&origNSGetExecutablePath);
        CFRelease(URL);
        
        // Just found out that it still needs the relocation workaround when the version is less than 2.6.
        // As most people won't care about the legacy versions anyway, I believe it doesn't mess up things so badly.
        BOOL hasRelocated = NO;
        if (CFBundleGetVersionNumber(GlyphsPythonMainBundle) < 1230) {
            // Relocate the executable inside the application bundle.
            // GlyphsCore.framework seems to have a dependency on GSFontTools.framework, and it tries to resolve
            // the dylib based on the path @executable_path/../Frameworks/GSFontTools.framework/Versions/A/GSFontTools.
            // Moreover, Glyphs.app apparently performs a self-integrity test on startup and silently aborts if you
            // put any files inside the bundle. To compensate for the situation, we temporarily relocate the executable
            // in /Application/Glyphs.app/Contents/MacOS and unlink it immediately when it is done.
            char self_path[PROC_PIDPATHINFO_MAXSIZE];
            if (proc_pidpath(getpid(), self_path, sizeof(self_path)) < 0) {
                fprintf(stderr, "error: failed to obtain path from pid\n");
                return 127;
            }
            argv[0] = self_path;
            
            char executable_path[PATH_MAX] = {0};
            strncpy(executable_path, [pathForGlyphsApp fileSystemRepresentation], PATH_MAX);
            strncat(executable_path, "/Contents/MacOS/", PATH_MAX);
            strncat(executable_path, basename((char *)argv[0]), PATH_MAX);
            if (strncmp(argv[0], executable_path, PATH_MAX) == 0) {
                // Seems to be launched inside the bundle; unlink the executable immediately.
                unlink(executable_path);
            } else {
                // Create a hard link inside the application bundle and launch it again.
                if (link(argv[0], executable_path) == 0) {
                    pid_t pid = fork();
                    if (pid == -1) {
                        fprintf(stderr, "error: failed to fork\n");
                        return 128;
                    } else if (pid > 0) {
                        int status;
                        waitpid(pid, &status, 0);
                        return WEXITSTATUS(status);
                    } else {
                        argv[0] = executable_path; // Rewrite argv[0] with the new path.
                        execv(executable_path, (char * const *)argv);
                        exit(EXIT_FAILURE);
                    }
                } else {
                    fprintf(stderr, "error: failed to create link: ");
                    perror(NULL);
                    return 129;
                }
            }
            hasRelocated = YES;
        }
        
        // Make sure to init the Python interpreter before loading Glyphs.
        Py_Initialize();
        {
            PyGILState_STATE state = PyGILState_Ensure();
            PyObject *path = PySys_GetObject("path");
            if (path) {
                
                PyList_Append(path, PyString_FromString([[NSFileManager defaultManager] fileSystemRepresentationWithPath:[[[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"Contents"] stringByAppendingPathComponent:@"Scripts"]]));
                PyList_Append(path, PyString_FromString([[NSFileManager defaultManager] fileSystemRepresentationWithPath:[[[NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject] stringByAppendingPathComponent:@"Glyphs"] stringByAppendingPathComponent:@"Scripts"]]));
            }
            PyGILState_Release(state);
        }
        
        ProcessSerialNumber psn = {0, kCurrentProcess};
        TransformProcessType(&psn, kProcessTransformToUIElementApplication);
        void *handle = dlopen([(hasRelocated ? (__bridge NSString *)GlyphsPythonMainBundleExecutablePath : [[NSBundle mainBundle] executablePath]) fileSystemRepresentation], RTLD_LOCAL);
        @autoreleasepool {
            [NSApplication sharedApplication];
            if (result == 0) {
                NSString *glyphsCoreFrameworkPath = [[[NSBundle mainBundle] sharedFrameworksPath] stringByAppendingPathComponent:@"GlyphsCore.framework"]; // @"/Applications/Glyphs.app/Frameworks/GlyphsCore.framework"
                [[NSBundle bundleWithPath:glyphsCoreFrameworkPath] load];
                if (!NSClassFromString(@"GSFont")) {
                    fprintf(stderr, "error: failed to load frameworks\n");
                    result = 132;
                } else {
                    // Load the built-in Python modules.
                    PyGILState_STATE state = PyGILState_Ensure();
                    PyObject *builtins = PyEval_GetBuiltins();
                    if (builtins) {
                        PyDict_Merge(builtins, PyModule_GetDict(PyImport_ImportModule("GlyphsApp")), 1);
                    }
                    PyGILState_Release(state);
                }
            }
            bool has_consumed_register_license_option = false;
            if (result == 0) {
                NSString *licensePath = nil;
                if (consume_register_license_option_if_available(&argc, argv, &licensePath)) {
                    if ([[[NSFileManager alloc] init] fileExistsAtPath:licensePath]) {
                        NSError *error = nil;
                        NSURL *licenseURL = [NSURL fileURLWithPath:licensePath relativeToURL:nil];
                        BOOL shouldDisableUI = [[NSUserDefaults standardUserDefaults] boolForKey:@"disableUI"];
                        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"disableUI"];
                        [[(id<GSInstallPluginDocumentProtocol>)[NSClassFromString(@"GSInstallPluginDocument") alloc] initWithContentsOfURL:licenseURL ofType:@"com.glyphsapp.glyphs2license" error:&error] description];
                        [[NSUserDefaults standardUserDefaults] setBool:shouldDisableUI forKey:@"disableUI"];
                        if (error) {
                            fprintf(stderr, "error: failed to register license\n");
                            result = 132;
                        }
                    } else {
                        fprintf(stderr, "error: no license file found at given path\n");
                        result = 1;
                    }
                    has_consumed_register_license_option = true;
                }
            }
            if (result == 0 && !has_consumed_register_license_option) {
                [(AppDelegate *)[[NSApplication sharedApplication] delegate] _loadAllPlugins];
                {
                    // Note that PyGILState_Ensure and PyGILState_Release are needed after Python plugins are loaded.
                    PyGILState_STATE state = PyGILState_Ensure();
                    result = Py_Main(argc, (char **)argv);
                    if (result == 0) {
                        // Tries to supresse the following message, but not sure if it's correct to do so:
                        //   Fatal Python error: auto-releasing thread-state, but no thread-state for this thread
                        PyGILState_Release(state);
                    }
                }
            }
        }
        dlclose(handle);
        
        PyGILState_STATE state = PyGILState_Ensure();
        Py_Finalize();
        PyGILState_Release(state);
    }
    return result;
}
