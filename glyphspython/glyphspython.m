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

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (nonatomic, readonly) NSArray<NSBundle *> *filterBundles;
@property (nonatomic, readonly) NSArray<NSBundle *> *fileFormatBundles;
@property (nonatomic, readonly) NSArray<NSBundle *> *paletteBundles;
@property (nonatomic, readonly) NSArray<NSBundle *> *customPluginBundles;
@end

@implementation AppDelegate

- (instancetype)init {
    if ((self = [super init])) {
        [self registerDefaults];
        NSMutableArray *mutableFilterBundles = [[NSMutableArray alloc] initWithCapacity:0];
        NSMutableArray *mutableFileFormatBundles = [[NSMutableArray alloc] initWithCapacity:0];
        for (NSString *filename in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[[NSBundle mainBundle] builtInPlugInsPath] error:nil]) {
            NSString *extension = [filename pathExtension];
            if ([extension isEqualToString:@"glyphsFilter"]) {
                NSBundle *bundle = [NSBundle bundleWithPath:[[[NSBundle mainBundle] builtInPlugInsPath] stringByAppendingPathComponent:filename]];
                if (bundle) {
                    [bundle load];
                    [mutableFilterBundles addObject:bundle];
                }
            } else if ([extension isEqualToString:@"glyphsFileFormat"]) {
                NSBundle *bundle = [NSBundle bundleWithPath:[[[NSBundle mainBundle] builtInPlugInsPath] stringByAppendingPathComponent:filename]];
                if (bundle) {
                    [bundle load];
                    [mutableFileFormatBundles addObject:bundle];
                }
            }
        }
        _filterBundles = [mutableFilterBundles copy];
        _fileFormatBundles = [mutableFileFormatBundles copy];
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

static int consume_register_licnse_option_if_available(int *argc, const char * argv[], NSString **path) {
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

int main(int _argc, const char * _argv[]) {
    // Provide a Python interpreter with some modules loaded using C API.
    int result = 0;
    //
    int argc = _argc;
    const char **argv = _argv;
    //
    @autoreleasepool {
        // Replace the exposed main bundle. As + [NSBundle mainBundle] calls CFBundleGetMainBundle() inside its implementation, the latter
        // Note that _NSGetExecutablePath() is also swizzled based on the assumption thCFPreferences resolves kCFPreferencesCurrentApplication based on
        // that value, but it doesn't seem to have any effects so far. Making sure to set up NSBundle/CFBundle/NSUserDefaults/CFPreferences is
        // especially important for Glyphs because it obtains the license information based on them and otherwise documents cannot be saved.
        // Note that mach_override is bundled with the project to override the builtin C functions.
        GlyphsPythonMainBundle = CFBundleCreate(NULL, (__bridge CFURLRef)[NSURL fileURLWithPath:[[NSWorkspace sharedWorkspace] absolutePathForAppBundleWithIdentifier:GlyphsAppIdentifier]]);
        CFURLRef URL = CFBundleCopyExecutableURL(GlyphsPythonMainBundle);
        GlyphsPythonMainBundleExecutablePath = CFURLCopyPath(URL);
        mach_override_ptr((void *)CFBundleGetMainBundle, (void *)GlyphsPythonCFBundleGetMainBundle, (void **)&origCFBundleGetMainBundle);
        mach_override_ptr((void *)_NSGetExecutablePath, (void *)GlyphsPythonNSGetExecutablePath, (void **)&origNSGetExecutablePath);
        CFRelease(URL);
        
        ProcessSerialNumber psn = {0, kCurrentProcess};
        TransformProcessType(&psn, kProcessTransformToUIElementApplication);
        void *handle = dlopen([[[NSBundle mainBundle] executablePath] fileSystemRepresentation], RTLD_LOCAL);
        @autoreleasepool {
            [NSApplication sharedApplication];
            if (result == 0) {
                NSString *glyphsCoreFrameworkPath = [[[NSBundle mainBundle] sharedFrameworksPath] stringByAppendingPathComponent:@"GlyphsCore.framework"]; // @"/Applications/Glyphs.app/Frameworks/GlyphsCore.framework"
                [[NSBundle bundleWithPath:glyphsCoreFrameworkPath] load];
                if (!NSClassFromString(@"GSFont")) {
                    fprintf(stderr, "error: failed to load frameworks\n");
                    result = 132;
                }
            }
            if (result == 0) {
                NSString *licensePath = nil;
                if (consume_register_licnse_option_if_available(&argc, argv, &licensePath)) {
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
                }
            }
            if (result == 0) {
                Py_Initialize();
                NSString *scriptsPath = [[[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"Contents"] stringByAppendingPathComponent:@"Scripts"]; // @"/Applications/Glyphs.app/Contents/Scripts";
                PyRun_SimpleStringFlags([[NSString stringWithFormat:
                                          @"import objc, sys;"
                                          @"sys.path.append(r'''%@''');"
                                          @"globals().update(__import__('GlyphsApp', globals(), locals()).__dict__);"
                                          @"globals()['__name__'] = '__main__';", scriptsPath] fileSystemRepresentation], NULL);
                result = Py_Main(argc, (char **)argv);
                Py_Finalize();
            }
        }
        dlclose(handle);
    }
    return result;
}
