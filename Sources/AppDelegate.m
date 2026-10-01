#import "AppDelegate.h"
#import "MainWindowController.h"

static NSMenuItem *AddItem(NSMenu *menu, NSString *title, SEL action, NSString *key, NSEventModifierFlags modifiers) {
    NSMenuItem *item = [menu addItemWithTitle:title action:action keyEquivalent:key];
    item.keyEquivalentModifierMask = modifiers;
    return item;
}

static NSMenu *AddSubmenu(NSMenu *mainMenu, NSString *title) {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:title];
    [mainMenu addItemWithTitle:title action:NULL keyEquivalent:@""].submenu = menu;
    return menu;
}

@implementation AppDelegate {
    MainWindowController *_windowController;
}

- (void)applicationWillFinishLaunching:(NSNotification *)notification {
    NSApp.mainMenu = [self makeMainMenu];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    _windowController = [[MainWindowController alloc] init];
    [_windowController showWindow:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

/// Menus are built in code because the app has no nib; nil-targeted items go through the responder chain.
- (NSMenu *)makeMainMenu {
    NSEventModifierFlags command = NSEventModifierFlagCommand;
    NSMenu *mainMenu = [[NSMenu alloc] init];

    NSMenu *app = AddSubmenu(mainMenu, @"Folder Size");
    AddItem(app, @"About Folder Size", @selector(orderFrontStandardAboutPanel:), @"", 0);
    [app addItem:[NSMenuItem separatorItem]];
    AddItem(app, @"Hide Folder Size", @selector(hide:), @"h", command);
    AddItem(app, @"Hide Others", @selector(hideOtherApplications:), @"h", command | NSEventModifierFlagOption);
    AddItem(app, @"Show All", @selector(unhideAllApplications:), @"", 0);
    [app addItem:[NSMenuItem separatorItem]];
    AddItem(app, @"Quit Folder Size", @selector(terminate:), @"q", command);

    NSMenu *file = AddSubmenu(mainMenu, @"File");
    AddItem(file, @"Scan", @selector(scanSelectedLocation:), @"r", command);
    AddItem(file, @"Choose Folder…", @selector(chooseFolder:), @"o", command);
    AddItem(file, @"Stop Scan", @selector(stopScan:), @".", command);
    [file addItem:[NSMenuItem separatorItem]];
    AddItem(file, @"Show in Finder", @selector(revealNode:), @"", 0);
    AddItem(file, @"Move to Trash…", @selector(trashNode:), @"\b", command);
    [file addItem:[NSMenuItem separatorItem]];
    AddItem(file, @"Close", @selector(performClose:), @"w", command);

    NSMenu *edit = AddSubmenu(mainMenu, @"Edit");
    AddItem(edit, @"Copy Path", @selector(copy:), @"c", command);

    NSMenu *view = AddSubmenu(mainMenu, @"View");
    unichar upArrow = NSUpArrowFunctionKey;
    AddItem(view, @"Up One Level", @selector(goUp:), [NSString stringWithCharacters:&upArrow length:1], command);

    NSMenu *window = AddSubmenu(mainMenu, @"Window");
    AddItem(window, @"Minimize", @selector(performMiniaturize:), @"m", command);
    AddItem(window, @"Zoom", @selector(performZoom:), @"", 0);
    NSApp.windowsMenu = window;

    return mainMenu;
}

@end
