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
        for (NSString *filename in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:@"/Applications/Glyphs.app/Contents/Plugins" error:nil]) {
            NSString *extension = [filename pathExtension];
            if ([extension isEqualToString:@"glyphsFilter"]) {
                NSBundle *bundle = [NSBundle bundleWithPath:[@"/Applications/Glyphs.app/Contents/Plugins" stringByAppendingPathComponent:filename]];
                if (bundle) {
                    [bundle load];
                    [mutableFilterBundles addObject:bundle];
                }
            } else if ([extension isEqualToString:@"glyphsFileFormat"]) {
                NSBundle *bundle = [NSBundle bundleWithPath:[@"/Applications/Glyphs.app/Contents/Plugins" stringByAppendingPathComponent:filename]];
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

@interface NSApplication (GSApplicationAdditions)
+ (NSApplication *)sharedApplication;
@end

@implementation NSApplication (GSApplicationAdditions)

+ (NSApplication *)sharedApplication {
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

@implementation NSBundle (NSBundleAdditions)

+ (void)load {
    // Swizzle + mainBundle to pretend as if it's launched from the inside of the bundle.
    // Note that CFBundleGetMainBundle() still returns the original bundle - if you want
    // to fix it, you may need to introduce another runtime function patching technique.
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class class = object_getClass(self);
        SEL originalSelector = @selector(mainBundle);
        SEL swizzledSelector = @selector(_mainBundle);
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
    
+ (NSBundle *)_mainBundle {
    static dispatch_once_t once_;
    static NSBundle *mainBundle = nil;
    dispatch_once(&once_, ^{
        mainBundle = [NSBundle bundleWithPath:@"/Applications/Glyphs.app"];
    });
    return mainBundle;
}

@end;

int main(int argc, const char * argv[]) {
    // Provide a Python interpreter with some modules loaded using C API.
    @autoreleasepool {
        ProcessSerialNumber psn = {0, kCurrentProcess};
        TransformProcessType(&psn, kProcessTransformToUIElementApplication);
        void *handle = dlopen("/Applications/Glyphs.app/Contents/MacOS/Glyphs", RTLD_LOCAL);
        [[NSBundle bundleWithPath:@"/Applications/Glyphs.app/Contents/Frameworks/GlyphsCore.framework"] load];
        if (!NSClassFromString(@"GSFont")) {
            fprintf(stderr, "error: failed to load frameworks\n");
            return 132;
        }
        Py_Initialize();
        PyRun_SimpleString("import objc, sys");
        PyRun_SimpleString("sys.path.append('/Applications/Glyphs.app/Contents/Scripts')");
        PyRun_SimpleString("globals().update(__import__('GlyphsApp', globals(), locals()).__dict__)");
        PyRun_SimpleString("globals()['__name__'] = '__main__'");
        Py_Main(argc, (char **)argv);
        Py_Finalize();
        dlclose(handle);
    }
    return 0;
}
