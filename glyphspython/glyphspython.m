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

int main(int argc, const char * argv[]) {
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
    strncpy(executable_path, "/Applications/Glyphs.app/Contents/MacOS/", PATH_MAX);
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
    // Provide a Python interpreter with some modules loaded using C API.
    @autoreleasepool {
        ProcessSerialNumber psn = {0, kCurrentProcess};
        TransformProcessType(&psn, kProcessTransformToUIElementApplication);
        void *handle = dlopen("/Applications/Glyphs.app/Contents/MacOS/Glyphs", RTLD_LOCAL);
        [[NSBundle bundleWithPath:@"/Applications/Glyphs.app/Contents/Frameworks/GlyphsCore.framework"] load];
        for (NSString *filename in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:@"/Applications/Glyphs.app/Contents/Plugins" error:nil]) {
            NSString *extension = [filename pathExtension];
            if ([extension isEqualToString:@"glyphsFilter"] || [extension isEqualToString:@"glyphsFileFormat"]) {
                [[NSBundle bundleWithPath:[@"/Applications/Glyphs.app/Contents/Plugins" stringByAppendingPathComponent:filename]] load];
            }
        }
        if (!NSClassFromString(@"GSFont")) {
            fprintf(stderr, "error: failed to load frameworks\n");
            return 132;
        }
        Py_Initialize();
        PyRun_SimpleString("import objc, sys");
        PyRun_SimpleString("sys.path.append('/Applications/Glyphs.app/Contents/Scripts')");
        PyRun_SimpleString("globals().update(__import__('GlyphsApp', globals(), locals()).__dict__)");
        Py_Main(argc, (char **)argv);
        Py_Finalize();
        dlclose(handle);
    }
    return 0;
}
