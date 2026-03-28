#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#include <spawn.h>
#include <sys/wait.h>

extern char **environ;

static void ShowAlert(NSString *title, NSString *message) {
    CFUserNotificationDisplayAlert(
        0,
        kCFUserNotificationStopAlertLevel,
        NULL,
        NULL,
        NULL,
        (__bridge CFStringRef)title,
        (__bridge CFStringRef)message,
        CFSTR("OK"),
        NULL,
        NULL,
        NULL);
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSString *resources = [[NSBundle mainBundle] resourcePath];
        if (resources.length == 0) {
            ShowAlert(@"Start Patched dLive",
                      @"Could not find the app resources folder.");
            return 1;
        }

        NSString *launcher = [resources stringByAppendingPathComponent:@"_launch_internal.sh"];
        if (![[NSFileManager defaultManager] isExecutableFileAtPath:launcher]) {
            ShowAlert(@"Start Patched dLive",
                      @"Internal launcher script is missing or not executable.");
            return 1;
        }

        setenv("MC_SHOW_LOG", "0", 1);

        const char *path = [launcher fileSystemRepresentation];
        char * const childArgv[] = {(char *)path, NULL};
        pid_t pid = 0;
        int rc = posix_spawn(&pid, path, NULL, NULL, childArgv, environ);
        if (rc != 0) {
            ShowAlert(@"Start Patched dLive",
                      [NSString stringWithFormat:@"Failed to start the patch launcher (error %d).", rc]);
            return rc;
        }

        return 0;
    }
}
