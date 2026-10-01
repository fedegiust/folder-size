#import <Cocoa/Cocoa.h>

@class FileNode, TreemapView;

@protocol TreemapViewDelegate <NSObject>
- (void)treemapView:(TreemapView *)view didClickNode:(FileNode *)node;
- (void)treemapView:(TreemapView *)view didDoubleClickNode:(FileNode *)node;
/// node is nil when the mouse leaves the map.
- (void)treemapView:(TreemapView *)view didHoverNode:(FileNode *)node;
- (NSMenu *)treemapView:(TreemapView *)view menuForNode:(FileNode *)node;
@end

/// Draws the contents of a folder as nested rectangles whose areas match their sizes.
/// Each item directly inside the folder gets its own color, shared by everything within it.
@interface TreemapView : NSView

@property (nonatomic, weak) id<TreemapViewDelegate> delegate;
/// The folder that fills the view.
@property (nonatomic, strong) FileNode *focusNode;
@property (nonatomic, strong) FileNode *selectedNode;
/// Shown instead of the map when there is nothing to draw.
@property (nonatomic, copy) NSString *placeholder;

/// Call after sizes or children in the tree changed.
- (void)reloadData;

@end
