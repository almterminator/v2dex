#import "AppDelegate.h"

#import <React/RCTBundleURLProvider.h>
#import <React/RCTRootView.h>

@implementation AppDelegate

- (NSRect)initialWindowFrame
{
  NSScreen *screen = NSScreen.mainScreen;
  NSRect visibleFrame = screen != nil ? screen.visibleFrame : NSMakeRect(0, 0, 1280, 720);
  CGFloat width = MIN(1280, NSWidth(visibleFrame) - 80);
  CGFloat height = MIN(760, NSHeight(visibleFrame) - 80);

  return NSMakeRect(
    NSMidX(visibleFrame) - width / 2,
    NSMidY(visibleFrame) - height / 2,
    width,
    height
  );
}

- (void)showMainWindow
{
  NSWindow *window = self.window;
  if (window == nil) {
    return;
  }

  NSRect frame = [self initialWindowFrame];
  window.title = @"V2Dex";
  window.minSize = NSMakeSize(960, 640);
  window.releasedWhenClosed = NO;
  window.backgroundColor = [NSColor colorWithRed:0.04 green:0.07 blue:0.11 alpha:1.0];
  window.opaque = YES;
  window.alphaValue = 1.0;
  window.level = NSNormalWindowLevel;
  window.sharingType = NSWindowSharingReadWrite;
  window.collectionBehavior = NSWindowCollectionBehaviorManaged;

  NSView *rootView = window.contentViewController.view;
  rootView.frame = NSMakeRect(0, 0, NSWidth(frame), NSHeight(frame));
  rootView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  rootView.wantsLayer = YES;
  rootView.layer.backgroundColor = [[NSColor colorWithRed:0.04 green:0.07 blue:0.11 alpha:1.0] CGColor];

  [window setFrame:frame display:YES animate:NO];
  [window displayIfNeeded];
  [window orderFrontRegardless];
  [window makeKeyAndOrderFront:nil];
  [NSApp activateIgnoringOtherApps:YES];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
  self.moduleName = @"V2Dex";
  // You can add your custom initial props in the dictionary below.
  // They will be passed down to the ViewController used by React Native.
  self.initialProps = @{};

  [super applicationDidFinishLaunching:notification];

  [self showMainWindow];
}

- (void)loadReactNativeWindow:(NSDictionary *)launchOptions
{
  NSRect frame = [self initialWindowFrame];
  RCTPlatformView *rootView = [self.rootViewFactory viewWithModuleName:self.moduleName
                                                     initialProperties:self.initialProps
                                                         launchOptions:launchOptions];
  rootView.frame = NSMakeRect(0, 0, NSWidth(frame), NSHeight(frame));
  rootView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

  NSViewController *rootViewController = [NSViewController new];
  rootViewController.view = rootView;

  self.window = [[NSWindow alloc] initWithContentRect:frame
                                            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable
                                              backing:NSBackingStoreBuffered
                                                defer:NO];
  self.window.contentViewController = rootViewController;
  [self showMainWindow];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag
{
  if (self.window != nil) {
    [self showMainWindow];
  }

  return YES;
}

- (void)customizeRootView:(RCTRootView *)rootView
{
  [super customizeRootView:rootView];
  rootView.wantsLayer = YES;
  rootView.layer.backgroundColor = [[NSColor colorWithRed:0.04 green:0.07 blue:0.11 alpha:1.0] CGColor];
}

- (NSURL *)sourceURLForBridge:(RCTBridge *)bridge
{
  return [self bundleURL];
}

- (NSURL *)bundleURL
{
#if DEBUG
  NSURL *providerURL = [[RCTBundleURLProvider sharedSettings] jsBundleURLForBundleRoot:@"index"];
  if (providerURL != nil) {
    return providerURL;
  }

  return [NSURL URLWithString:@"http://127.0.0.1:8081/index.bundle?platform=macos&dev=true&minify=false"];
#else
  return [[NSBundle mainBundle] URLForResource:@"main" withExtension:@"jsbundle"];
#endif
}

/// This method controls whether the `concurrentRoot`feature of React18 is turned on or off.
///
/// @see: https://reactjs.org/blog/2022/03/29/react-v18.html
/// @note: This requires to be rendering on Fabric (i.e. on the New Architecture).
/// @return: `true` if the `concurrentRoot` feature is enabled. Otherwise, it returns `false`.
- (BOOL)concurrentRootEnabled
{
#ifdef RN_FABRIC_ENABLED
  return true;
#else
  return false;
#endif
}

@end
