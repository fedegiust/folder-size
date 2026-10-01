#import "MainWindowController.h"
#import "FileNode.h"
#import "PercentBarView.h"
#import "Scanner.h"
#import "TreemapView.h"

static NSString *const kNameColumn = @"name";
static NSString *const kSizeColumn = @"size";
static NSString *const kPercentColumn = @"percent";
static NSString *const kFilesColumn = @"files";
static NSString *const kFullDiskAccessURL = @"x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles";

@interface MainWindowController () <NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate, TreemapViewDelegate>
@end

@implementation MainWindowController {
    NSPopUpButton *_locationPopUp;
    NSButton *_scanButton;
    NSButton *_chooseButton;
    NSButton *_stopButton;
    NSButton *_upButton;
    NSButton *_fullDiskAccessButton;
    NSProgressIndicator *_spinner;
    NSTextField *_focusLabel;
    NSTextField *_statusLabel;
    NSTextField *_hoverLabel;
    NSOutlineView *_outlineView;
    TreemapView *_treemapView;

    FileNode *_root;
    Scanner *_scanner;
    BOOL _isSyncingSelection;  // set while we select rows ourselves, so the map is not refocused
    NSMutableDictionary<NSString *, NSImage *> *_iconsByExtension;
}

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1100, 700)
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                             | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"Folder Size";
    window.minSize = NSMakeSize(760, 420);
    if ((self = [super initWithWindow:window])) {
        _iconsByExtension = [NSMutableDictionary dictionary];
        [self buildInterface];
        [self reloadLocations];
        [self observeVolumeChanges];
        [self updateControls];
        [window center];
        window.frameAutosaveName = @"MainWindow";
    }
    return self;
}

- (void)dealloc {
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
}

#pragma mark - Building the window

- (void)buildInterface {
    NSView *content = self.window.contentView;

    _locationPopUp = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_locationPopUp.widthAnchor constraintGreaterThanOrEqualToConstant:300].active = YES;
    _scanButton = [NSButton buttonWithTitle:@"Scan" target:self action:@selector(scanSelectedLocation:)];
    _scanButton.keyEquivalent = @"\r";
    _chooseButton = [NSButton buttonWithTitle:@"Choose Folder…" target:self action:@selector(chooseFolder:)];
    _stopButton = [NSButton buttonWithTitle:@"Stop" target:self action:@selector(stopScan:)];
    _spinner = [[NSProgressIndicator alloc] init];
    _spinner.style = NSProgressIndicatorStyleSpinning;
    _spinner.controlSize = NSControlSizeSmall;
    _spinner.displayedWhenStopped = NO;
    NSStackView *toolbar = [NSStackView stackViewWithViews:@[ _locationPopUp, _scanButton, _chooseButton, _stopButton, _spinner ]];
    toolbar.spacing = 8;

    NSSplitView *split = [[NSSplitView alloc] initWithFrame:NSMakeRect(0, 0, 1100, 600)];
    split.vertical = YES;
    split.dividerStyle = NSSplitViewDividerStyleThin;
    [split addSubview:[self makeTreePaneWithFrame:NSMakeRect(0, 0, 540, 600)]];
    [split addSubview:[self makeMapPaneWithFrame:NSMakeRect(541, 0, 559, 600)]];
    [split adjustSubviews];
    split.autosaveName = @"MainSplit";

    _statusLabel = [self labelWithFont:[NSFont systemFontOfSize:12] color:[NSColor secondaryLabelColor]];
    _fullDiskAccessButton = [NSButton buttonWithTitle:@"Grant Full Disk Access…" target:self action:@selector(explainFullDiskAccess:)];
    _fullDiskAccessButton.controlSize = NSControlSizeSmall;
    _fullDiskAccessButton.font = [NSFont systemFontOfSize:11];
    _fullDiskAccessButton.hidden = YES;
    _hoverLabel = [self labelWithFont:[NSFont systemFontOfSize:12] color:[NSColor secondaryLabelColor]];
    _hoverLabel.lineBreakMode = NSLineBreakByTruncatingHead;
    _hoverLabel.alignment = NSTextAlignmentRight;
    NSStackView *statusBar = [[NSStackView alloc] init];
    [statusBar addView:_statusLabel inGravity:NSStackViewGravityLeading];
    [statusBar addView:_fullDiskAccessButton inGravity:NSStackViewGravityLeading];
    [statusBar addView:_hoverLabel inGravity:NSStackViewGravityTrailing];

    for (NSView *view in @[ toolbar, split, statusBar ]) {
        view.translatesAutoresizingMaskIntoConstraints = NO;
        [content addSubview:view];
    }
    [NSLayoutConstraint activateConstraints:@[
        [toolbar.topAnchor constraintEqualToAnchor:content.topAnchor constant:10],
        [toolbar.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:12],
        [toolbar.trailingAnchor constraintLessThanOrEqualToAnchor:content.trailingAnchor constant:-12],
        [split.topAnchor constraintEqualToAnchor:toolbar.bottomAnchor constant:10],
        [split.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [split.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [statusBar.topAnchor constraintEqualToAnchor:split.bottomAnchor constant:6],
        [statusBar.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:12],
        [statusBar.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-12],
        [statusBar.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-6],
    ]];
}

- (NSView *)makeTreePaneWithFrame:(NSRect)frame {
    _outlineView = [[NSOutlineView alloc] init];
    NSTableColumn *nameColumn = [self addColumn:kNameColumn title:@"Name" width:200 alignment:NSTextAlignmentLeft];
    [self addColumn:kSizeColumn title:@"Size" width:75 alignment:NSTextAlignmentRight];
    [self addColumn:kPercentColumn title:@"% of Parent" width:115 alignment:NSTextAlignmentLeft];
    [self addColumn:kFilesColumn title:@"Files" width:70 alignment:NSTextAlignmentRight];
    _outlineView.outlineTableColumn = nameColumn;
    _outlineView.columnAutoresizingStyle = NSTableViewFirstColumnOnlyAutoresizingStyle;
    _outlineView.rowHeight = 20;
    _outlineView.usesAlternatingRowBackgroundColors = YES;
    _outlineView.dataSource = self;
    _outlineView.delegate = self;
    _outlineView.target = self;
    _outlineView.doubleAction = @selector(outlineDoubleClicked:);
    _outlineView.menu = [[NSMenu alloc] init];
    _outlineView.menu.delegate = self;
    _outlineView.autosaveName = @"FolderTree";
    _outlineView.autosaveTableColumns = YES;

    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:frame];
    scrollView.documentView = _outlineView;
    scrollView.hasVerticalScroller = YES;
    scrollView.hasHorizontalScroller = YES;
    scrollView.autohidesScrollers = YES;
    return scrollView;
}

- (NSTableColumn *)addColumn:(NSString *)identifier title:(NSString *)title width:(CGFloat)width alignment:(NSTextAlignment)alignment {
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:identifier];
    column.title = title;
    column.width = width;
    column.minWidth = 50;
    column.headerCell.alignment = alignment;
    [_outlineView addTableColumn:column];
    return column;
}

- (NSView *)makeMapPaneWithFrame:(NSRect)frame {
    NSView *pane = [[NSView alloc] initWithFrame:frame];

    _upButton = [NSButton buttonWithTitle:@"↑ Up" target:self action:@selector(goUp:)];
    _upButton.controlSize = NSControlSizeSmall;
    _upButton.font = [NSFont systemFontOfSize:11];
    _focusLabel = [self labelWithFont:[NSFont boldSystemFontOfSize:12] color:[NSColor labelColor]];
    _focusLabel.lineBreakMode = NSLineBreakByTruncatingHead;
    NSStackView *header = [NSStackView stackViewWithViews:@[ _upButton, _focusLabel ]];

    _treemapView = [[TreemapView alloc] init];
    _treemapView.delegate = self;

    for (NSView *view in @[ header, _treemapView ]) {
        view.translatesAutoresizingMaskIntoConstraints = NO;
        [pane addSubview:view];
    }
    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:pane.topAnchor constant:6],
        [header.leadingAnchor constraintEqualToAnchor:pane.leadingAnchor constant:8],
        [header.trailingAnchor constraintLessThanOrEqualToAnchor:pane.trailingAnchor constant:-8],
        [_treemapView.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:6],
        [_treemapView.leadingAnchor constraintEqualToAnchor:pane.leadingAnchor constant:6],
        [_treemapView.trailingAnchor constraintEqualToAnchor:pane.trailingAnchor constant:-6],
        [_treemapView.bottomAnchor constraintEqualToAnchor:pane.bottomAnchor],
        [_treemapView.widthAnchor constraintGreaterThanOrEqualToConstant:200],
    ]];
    return pane;
}

- (NSTextField *)labelWithFont:(NSFont *)font color:(NSColor *)color {
    NSTextField *label = [NSTextField labelWithString:@""];
    label.font = font;
    label.textColor = color;
    label.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    return label;
}

#pragma mark - Drives and folders to scan

- (void)observeVolumeChanges {
    NSNotificationCenter *center = [[NSWorkspace sharedWorkspace] notificationCenter];
    for (NSString *name in @[ NSWorkspaceDidMountNotification, NSWorkspaceDidUnmountNotification,
                              NSWorkspaceDidRenameVolumeNotification ]) {
        [center addObserver:self selector:@selector(volumesDidChange:) name:name object:nil];
    }
}

- (void)volumesDidChange:(NSNotification *)notification {
    [self reloadLocations];
}

/// Fills the picker with the home folder and every mounted drive: internal, external, disk images and network shares.
- (void)reloadLocations {
    NSString *previousPath = _locationPopUp.selectedItem.representedObject ?: @"/";
    NSMenu *menu = _locationPopUp.menu;
    [menu removeAllItems];

    [self addLocationWithTitle:@"Home Folder" path:NSHomeDirectory() toMenu:menu];
    [menu addItem:[NSMenuItem separatorItem]];

    NSArray<NSURLResourceKey> *keys = @[ NSURLVolumeNameKey, NSURLVolumeTotalCapacityKey,
                                         NSURLVolumeAvailableCapacityForImportantUsageKey, NSURLVolumeAvailableCapacityKey ];
    NSArray<NSURL *> *volumes = [[NSFileManager defaultManager] mountedVolumeURLsIncludingResourceValuesForKeys:keys
                                                                                                        options:NSVolumeEnumerationSkipHiddenVolumes];
    for (NSURL *volume in volumes) {
        NSDictionary<NSURLResourceKey, id> *values = [volume resourceValuesForKeys:keys error:nil];
        NSString *name = values[NSURLVolumeNameKey] ?: volume.path.lastPathComponent;
        NSNumber *total = values[NSURLVolumeTotalCapacityKey];
        // "Important usage" counts purgeable space as free, like Finder does; not every volume reports it.
        NSNumber *available = values[NSURLVolumeAvailableCapacityForImportantUsageKey] ?: values[NSURLVolumeAvailableCapacityKey];
        NSString *title = name;
        if (total && available) {
            title = [NSString stringWithFormat:@"%@ — %@ free of %@", name,
                     FormatBytes(available.unsignedLongLongValue), FormatBytes(total.unsignedLongLongValue)];
        }
        [self addLocationWithTitle:title path:volume.path toMenu:menu];
    }

    NSInteger index = [menu indexOfItemWithRepresentedObject:previousPath];
    if (index < 0) index = [menu indexOfItemWithRepresentedObject:@"/"];
    [_locationPopUp selectItemAtIndex:MAX(index, 0)];
}

- (void)addLocationWithTitle:(NSString *)title path:(NSString *)path toMenu:(NSMenu *)menu {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:NULL keyEquivalent:@""];
    item.representedObject = path;
    NSImage *icon = [[[NSWorkspace sharedWorkspace] iconForFile:path] copy];
    icon.size = NSMakeSize(16, 16);
    item.image = icon;
    [menu addItem:item];
}

#pragma mark - Scanning

- (IBAction)scanSelectedLocation:(id)sender {
    NSString *path = _locationPopUp.selectedItem.representedObject;
    if (path) [self scanPath:path replacingNode:nil];
}

- (IBAction)chooseFolder:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseDirectories = YES;
    panel.canChooseFiles = NO;
    panel.showsHiddenFiles = YES;
    panel.treatsFilePackagesAsDirectories = YES;
    panel.prompt = @"Scan";
    panel.message = @"Choose a folder or drive to scan.";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response == NSModalResponseOK) [self scanPath:panel.URL.path replacingNode:nil];
    }];
}

/// The window is released at once: the scan may be stuck inside a single system call
/// (a privacy prompt, a slow network share) and only notices the cancellation after it returns.
- (IBAction)stopScan:(id)sender {
    [_scanner cancel];
    _scanner = nil;
    _statusLabel.stringValue = @"Scan stopped.";
    [self updateControls];
}

/// With oldNode, the result replaces that folder inside the current tree instead of replacing the whole tree.
- (void)scanPath:(NSString *)path replacingNode:(FileNode *)oldNode {
    if (_scanner) return;
    Scanner *scanner = [[Scanner alloc] initWithRootPath:path];
    _scanner = scanner;
    _fullDiskAccessButton.hidden = YES;
    _statusLabel.stringValue = [NSString stringWithFormat:@"Scanning %@…", path];
    [self updateControls];

    [scanner startWithProgress:^(unsigned long long fileCount, unsigned long long byteCount, NSString *currentFolder) {
        if (self->_scanner != scanner) return;
        self->_statusLabel.stringValue = [NSString stringWithFormat:@"Scanning… %@ files, %@ — %@",
                                          FormatCount(fileCount), FormatBytes(byteCount), currentFolder];
    } completion:^(FileNode *result) {
        if (self->_scanner != scanner) return;  // stopped earlier
        self->_scanner = nil;
        [self updateControls];
        if (!result) {
            self->_statusLabel.stringValue = [NSString stringWithFormat:@"Could not read %@.", path];
            return;
        }
        if (oldNode) {
            [self replaceNode:oldNode withNode:result];
        } else {
            [self showTree:result];
        }
        [self showSummaryForNode:result scanner:scanner];
    }];
}

- (void)showSummaryForNode:(FileNode *)node scanner:(Scanner *)scanner {
    NSMutableString *summary = [NSMutableString stringWithFormat:@"%@: %@ in %@ files, scanned in %.1f s",
                                [self displayNameForNode:node], FormatBytes(node.size), FormatCount(node.fileCount), scanner.duration];
    if (scanner.unreadableFolderCount > 0) {
        [summary appendFormat:@" · %@ folders could not be read", FormatCount(scanner.unreadableFolderCount)];
        if (@available(macOS 10.14, *)) {
            _fullDiskAccessButton.hidden = NO;
        }
    }
    _statusLabel.stringValue = summary;
}

- (IBAction)explainFullDiskAccess:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Let Folder Size read protected folders";
    alert.informativeText = @"macOS keeps some folders (Mail, Messages, Safari, other apps' data) private until you allow it.\n\n"
                            @"1. In Privacy settings, open Full Disk Access.\n"
                            @"2. Turn on Folder Size, or add it with the + button.\n"
                            @"3. Quit and reopen Folder Size, then scan again.";
    [alert addButtonWithTitle:@"Open Privacy Settings"];
    [alert addButtonWithTitle:@"Cancel"];
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response == NSAlertFirstButtonReturn) {
            [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:kFullDiskAccessURL]];
        }
    }];
}

- (void)updateControls {
    BOOL scanning = _scanner != nil;
    _scanButton.enabled = !scanning;
    _chooseButton.enabled = !scanning;
    _locationPopUp.enabled = !scanning;
    _stopButton.enabled = scanning;
    _treemapView.placeholder = scanning ? @"Scanning…" : @"Pick a drive or folder, then click Scan.";
    if (scanning) {
        [_spinner startAnimation:nil];
    } else {
        [_spinner stopAnimation:nil];
    }
    _upButton.enabled = _treemapView.focusNode.parent != nil;
}

#pragma mark - Showing and changing the tree

- (void)showTree:(FileNode *)root {
    _root = root;
    [_outlineView reloadData];
    [_outlineView expandItem:root];
    _treemapView.selectedNode = nil;
    [self showFolderInMap:root];
    self.window.title = [NSString stringWithFormat:@"Folder Size — %@", root.path];
    self.window.representedURL = root.fileURL;
}

- (void)showFolderInMap:(FileNode *)folder {
    _treemapView.focusNode = folder;
    _focusLabel.stringValue = folder ? [NSString stringWithFormat:@"%@ — %@", folder.path, FormatBytes(folder.size)] : @"";
    [self updateControls];
}

- (void)replaceNode:(FileNode *)oldNode withNode:(FileNode *)newNode {
    FileNode *parent = oldNode.parent;
    if (!parent) {
        [self showTree:newNode];
        return;
    }
    newNode.name = oldNode.name;  // a scan names its root with the full path
    newNode.isHidden = oldNode.isHidden;
    BOOL mapWasInside = [_treemapView.focusNode isDescendantOf:oldNode];
    [parent replaceChild:oldNode withNode:newNode];
    [self reloadTreeKeepingExpandedFolders];
    [self showFolderInMap:(mapWasInside ? newNode : _treemapView.focusNode)];
    [self revealInOutline:newNode];
}

- (void)removeNodeFromTree:(FileNode *)node {
    FileNode *parent = node.parent;
    BOOL mapWasInside = [_treemapView.focusNode isDescendantOf:node];
    [parent removeChild:node];
    _treemapView.selectedNode = nil;
    [self reloadTreeKeepingExpandedFolders];
    [self showFolderInMap:(mapWasInside ? parent : _treemapView.focusNode)];
    [self revealInOutline:parent];
}

- (void)reloadTreeKeepingExpandedFolders {
    NSMutableArray<FileNode *> *expanded = [NSMutableArray array];
    for (NSInteger row = 0; row < _outlineView.numberOfRows; row++) {
        id item = [_outlineView itemAtRow:row];
        if ([_outlineView isItemExpanded:item]) [expanded addObject:item];
    }
    [_outlineView reloadData];
    for (FileNode *item in expanded) {
        if ([item isDescendantOf:_root]) [_outlineView expandItem:item];
    }
}

- (void)revealInOutline:(FileNode *)node {
    NSMutableArray<FileNode *> *ancestors = [NSMutableArray array];
    for (FileNode *ancestor = node.parent; ancestor; ancestor = ancestor.parent) [ancestors insertObject:ancestor atIndex:0];
    for (FileNode *ancestor in ancestors) [_outlineView expandItem:ancestor];

    NSInteger row = [_outlineView rowForItem:node];
    if (row < 0) return;
    _isSyncingSelection = YES;
    [_outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
    _isSyncingSelection = NO;
    [_outlineView scrollRowToVisible:row];
}

- (FileNode *)selectedNode {
    NSInteger row = _outlineView.selectedRow;
    return row >= 0 ? [_outlineView itemAtRow:row] : nil;
}

- (NSString *)displayNameForNode:(FileNode *)node {
    if (node.parent) return node.name;
    // "/" is clearer as the disk's name; other roots show their full path.
    return [node.path isEqualToString:@"/"] ? [[NSFileManager defaultManager] displayNameAtPath:@"/"] : node.path;
}

#pragma mark - Outline data source and delegate

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(FileNode *)item {
    if (!item) return _root ? 1 : 0;
    return (NSInteger)item.children.count;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(FileNode *)item {
    return item ? item.children[(NSUInteger)index] : _root;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(FileNode *)item {
    return item.children.count > 0;
}

- (NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(NSTableColumn *)column item:(FileNode *)node {
    NSString *identifier = column.identifier;

    if ([identifier isEqualToString:kPercentColumn]) {
        PercentBarView *bar = [outlineView makeViewWithIdentifier:identifier owner:self];
        if (!bar) {
            bar = [[PercentBarView alloc] init];
            bar.identifier = identifier;
        }
        bar.fraction = node.parent.size > 0 ? (double)node.size / (double)node.parent.size : 1;
        return bar;
    }

    NSTableCellView *cell = [outlineView makeViewWithIdentifier:identifier owner:self] ?: [self makeCellWithIdentifier:identifier];
    cell.textField.textColor = node.isHidden ? [NSColor secondaryLabelColor] : [NSColor labelColor];
    if ([identifier isEqualToString:kNameColumn]) {
        NSString *name = [self displayNameForNode:node];
        cell.textField.stringValue = node.isUnreadable ? [name stringByAppendingString:@"  (no access)"] : name;
        cell.imageView.image = [self iconForNode:node];
    } else if ([identifier isEqualToString:kSizeColumn]) {
        cell.textField.stringValue = FormatBytes(node.size);
    } else if ([identifier isEqualToString:kFilesColumn]) {
        cell.textField.stringValue = node.isFolder ? FormatCount(node.fileCount) : @"";
    }
    return cell;
}

- (NSTableCellView *)makeCellWithIdentifier:(NSString *)identifier {
    NSTableCellView *cell = [[NSTableCellView alloc] init];
    cell.identifier = identifier;
    NSTextField *text = [NSTextField labelWithString:@""];
    text.translatesAutoresizingMaskIntoConstraints = NO;
    [cell addSubview:text];
    cell.textField = text;

    if ([identifier isEqualToString:kNameColumn]) {
        text.lineBreakMode = NSLineBreakByTruncatingMiddle;
        NSImageView *image = [[NSImageView alloc] init];
        image.imageScaling = NSImageScaleProportionallyDown;
        image.translatesAutoresizingMaskIntoConstraints = NO;
        [cell addSubview:image];
        cell.imageView = image;
        [NSLayoutConstraint activateConstraints:@[
            [image.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:2],
            [image.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            [image.widthAnchor constraintEqualToConstant:16],
            [image.heightAnchor constraintEqualToConstant:16],
            [text.leadingAnchor constraintEqualToAnchor:image.trailingAnchor constant:5],
        ]];
    } else {
        text.alignment = NSTextAlignmentRight;
        text.font = [NSFont monospacedDigitSystemFontOfSize:[NSFont systemFontSize] weight:NSFontWeightRegular];
        [text.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:2].active = YES;
    }
    [NSLayoutConstraint activateConstraints:@[
        [text.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-4],
        [text.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
    ]];
    return cell;
}

- (NSImage *)iconForNode:(FileNode *)node {
    NSString *extension = node.name.pathExtension.lowercaseString;
    // The root and bundles such as .app have their own icons; everything else shares one per type.
    if (!node.parent || (node.isFolder && extension.length > 0)) {
        return [[NSWorkspace sharedWorkspace] iconForFile:node.path];
    }
    NSString *key = node.isFolder ? @"/folder" : extension;
    NSImage *icon = _iconsByExtension[key];
    if (!icon) {
        icon = node.isFolder ? [NSImage imageNamed:NSImageNameFolder] : [[NSWorkspace sharedWorkspace] iconForFileType:extension];
        _iconsByExtension[key] = icon;
    }
    return icon;
}

/// Selecting a folder shows it in the map; selecting a file shows its folder and highlights the file.
- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
    if (_isSyncingSelection) return;
    FileNode *node = self.selectedNode;
    if (!node) return;
    if (node.isFolder) {
        _treemapView.selectedNode = nil;
        [self showFolderInMap:node];
    } else {
        [self showFolderInMap:node.parent];
        _treemapView.selectedNode = node;
    }
}

- (void)outlineDoubleClicked:(id)sender {
    NSInteger row = _outlineView.clickedRow;
    if (row < 0) return;
    FileNode *node = [_outlineView itemAtRow:row];
    if (!node.isFolder) {
        [self revealNode:node];
    } else if ([_outlineView isItemExpanded:node]) {
        [_outlineView collapseItem:node];
    } else {
        [_outlineView expandItem:node];
    }
}

#pragma mark - Treemap delegate

- (void)treemapView:(TreemapView *)view didClickNode:(FileNode *)node {
    view.selectedNode = node;
    [self revealInOutline:node];
}

/// Zooms into the folder under the mouse that sits directly inside the one being shown.
- (void)treemapView:(TreemapView *)view didDoubleClickNode:(FileNode *)node {
    FileNode *child = node;
    while (child.parent && child.parent != view.focusNode) child = child.parent;
    if (child.parent == view.focusNode && child.children.count > 0) {
        view.selectedNode = nil;
        [self showFolderInMap:child];
        [self revealInOutline:child];
    }
}

- (void)treemapView:(TreemapView *)view didHoverNode:(FileNode *)node {
    _hoverLabel.stringValue = node ? [NSString stringWithFormat:@"%@ — %@", node.path, FormatBytes(node.size)] : @"";
}

- (NSMenu *)treemapView:(TreemapView *)view menuForNode:(FileNode *)node {
    NSMenu *menu = [[NSMenu alloc] init];
    [self addActionsForNode:node toMenu:menu];
    return menu;
}

- (IBAction)goUp:(id)sender {
    FileNode *parent = _treemapView.focusNode.parent;
    if (!parent) return;
    _treemapView.selectedNode = nil;
    [self showFolderInMap:parent];
    [self revealInOutline:parent];
}

#pragma mark - Actions on files and folders

- (void)menuNeedsUpdate:(NSMenu *)menu {
    [menu removeAllItems];
    NSInteger row = _outlineView.clickedRow;
    if (row >= 0) [self addActionsForNode:[_outlineView itemAtRow:row] toMenu:menu];
}

- (void)addActionsForNode:(FileNode *)node toMenu:(NSMenu *)menu {
    [self addItemTitled:@"Open" action:@selector(openNode:) node:node toMenu:menu];
    [self addItemTitled:@"Show in Finder" action:@selector(revealNode:) node:node toMenu:menu];
    [self addItemTitled:@"Copy Path" action:@selector(copy:) node:node toMenu:menu];
    if (node.isFolder) {
        [menu addItem:[NSMenuItem separatorItem]];
        [self addItemTitled:@"Show in Map" action:@selector(showNodeInMap:) node:node toMenu:menu];
        [self addItemTitled:@"Rescan This Folder" action:@selector(rescanNode:) node:node toMenu:menu];
    }
    [menu addItem:[NSMenuItem separatorItem]];
    [self addItemTitled:@"Move to Trash…" action:@selector(trashNode:) node:node toMenu:menu];
}

- (void)addItemTitled:(NSString *)title action:(SEL)action node:(FileNode *)node toMenu:(NSMenu *)menu {
    NSMenuItem *item = [menu addItemWithTitle:title action:action keyEquivalent:@""];
    item.target = self;
    item.representedObject = node;
}

/// Context-menu items carry their node; main-menu items act on the selected row.
- (FileNode *)nodeForAction:(id)sender {
    if ([sender isKindOfClass:[FileNode class]]) return sender;
    id object = [sender respondsToSelector:@selector(representedObject)] ? [sender representedObject] : nil;
    return [object isKindOfClass:[FileNode class]] ? object : self.selectedNode;
}

- (IBAction)openNode:(id)sender {
    FileNode *node = [self nodeForAction:sender];
    if (node) [[NSWorkspace sharedWorkspace] openURL:node.fileURL];
}

- (IBAction)revealNode:(id)sender {
    FileNode *node = [self nodeForAction:sender];
    if (node) [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[ node.fileURL ]];
}

- (IBAction)copy:(id)sender {
    FileNode *node = [self nodeForAction:sender];
    if (!node) return;
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard setString:node.path forType:NSPasteboardTypeString];
}

- (IBAction)showNodeInMap:(id)sender {
    FileNode *node = [self nodeForAction:sender];
    if (!node.isFolder) return;
    _treemapView.selectedNode = nil;
    [self showFolderInMap:node];
    [self revealInOutline:node];
}

- (IBAction)rescanNode:(id)sender {
    FileNode *node = [self nodeForAction:sender];
    if (node.isFolder) [self scanPath:node.path replacingNode:node];
}

- (IBAction)trashNode:(id)sender {
    FileNode *node = [self nodeForAction:sender];
    if (!node.parent || _scanner) return;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"Move “%@” to the Trash?", node.name];
    alert.informativeText = [NSString stringWithFormat:@"It uses %@ on disk. The space is freed when you empty the Trash.", FormatBytes(node.size)];
    [alert addButtonWithTitle:@"Move to Trash"];
    [alert addButtonWithTitle:@"Cancel"];
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response != NSAlertFirstButtonReturn) return;
        NSError *error = nil;
        if (![[NSFileManager defaultManager] trashItemAtURL:node.fileURL resultingItemURL:nil error:&error]) {
            [[NSAlert alertWithError:error] beginSheetModalForWindow:self.window completionHandler:nil];
            return;
        }
        [self removeNodeFromTree:node];
    }];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    SEL action = item.action;
    BOOL scanning = _scanner != nil;
    if (action == @selector(scanSelectedLocation:) || action == @selector(chooseFolder:) || action == @selector(rescanNode:)) {
        return !scanning;
    }
    if (action == @selector(stopScan:)) return scanning;
    if (action == @selector(goUp:)) return _treemapView.focusNode.parent != nil;
    if (action == @selector(trashNode:)) return !scanning && [self nodeForAction:item].parent != nil;
    if (action == @selector(copy:) || action == @selector(revealNode:) || action == @selector(openNode:)) {
        return [self nodeForAction:item] != nil;
    }
    return YES;
}

@end
