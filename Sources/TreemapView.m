#import "TreemapView.h"
#import "FileNode.h"

static const CGFloat kMinimumSide = 2;         // smaller rectangles are not worth drawing
static const CGFloat kHeaderHeight = 16;       // folder name strip above a folder's contents
static const NSUInteger kMaximumCells = 60000; // keeps drawing fast on huge trees

/// One rectangle in the map.
@interface TreemapCell : NSObject
@property (nonatomic, strong) FileNode *node;
@property (nonatomic) NSRect rect;
@property (nonatomic, strong) NSColor *color;
@property (nonatomic) BOOL hasHeader;
@property (nonatomic) BOOL hasChildCells;
@end

@implementation TreemapCell
@end

static NSColor *CellColor(NSInteger branch, NSInteger depth, BOOL isFolder) {
    static const CGFloat hues[] = { 0.58, 0.08, 0.36, 0.97, 0.75, 0.14, 0.50, 0.88, 0.03, 0.66 };
    CGFloat hue = hues[branch % (NSInteger)(sizeof(hues) / sizeof(hues[0]))];
    CGFloat brightness = isFolder ? MAX(0.35, 0.72 - 0.07 * depth) : MAX(0.45, 0.92 - 0.06 * depth);
    return [NSColor colorWithCalibratedHue:hue saturation:(isFolder ? 0.50 : 0.55) brightness:brightness alpha:1];
}

/// Rounds the edges, not the size, so neighbouring rectangles neither overlap nor leave gaps.
static NSRect PixelAligned(NSRect rect) {
    CGFloat minX = round(NSMinX(rect)), minY = round(NSMinY(rect));
    return NSMakeRect(minX, minY, round(NSMaxX(rect)) - minX, round(NSMaxY(rect)) - minY);
}

/// How far from square the worst rectangle in a row would be (1 is a perfect square).
static double WorstAspectRatio(double largestArea, double smallestArea, double rowArea, double side) {
    double side2 = side * side, row2 = rowArea * rowArea;
    return MAX(side2 * largestArea / row2, row2 / (side2 * smallestArea));
}

@implementation TreemapView {
    NSMutableArray<TreemapCell *> *_cells;  // parents before their children, so drawing in order nests correctly
    BOOL _needsCellLayout;
    FileNode *_hoveredNode;
}

- (BOOL)isFlipped {
    return YES;
}

- (void)setFocusNode:(FileNode *)focusNode {
    _focusNode = focusNode;
    [self reloadData];
}

- (void)setPlaceholder:(NSString *)placeholder {
    _placeholder = [placeholder copy];
    [self setNeedsDisplay:YES];
}

- (void)setSelectedNode:(FileNode *)selectedNode {
    _selectedNode = selectedNode;
    [self setNeedsDisplay:YES];
}

- (void)reloadData {
    _needsCellLayout = YES;
    _hoveredNode = nil;
    [self setNeedsDisplay:YES];
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    _needsCellLayout = YES;
}

#pragma mark - Layout

- (void)layOutCellsIfNeeded {
    if (!_needsCellLayout) return;
    _needsCellLayout = NO;
    _cells = [NSMutableArray array];
    if (self.focusNode.isFolder) {
        [self layOutChildrenOf:self.focusNode inRect:self.bounds depth:0 branch:0];
    }
}

/// Squarified treemap (Bruls, Huizing & van Wijk): children are placed in rows along the shorter
/// side of the free space, and a row keeps growing while that makes its rectangles squarer.
- (void)layOutChildrenOf:(FileNode *)folder inRect:(NSRect)rect depth:(NSInteger)depth branch:(NSInteger)branch {
    NSArray<FileNode *> *children = folder.children;
    double total = 0;
    for (FileNode *child in children) total += child.size;
    if (total <= 0 || NSWidth(rect) < kMinimumSide || NSHeight(rect) < kMinimumSide) return;

    double areaPerByte = NSWidth(rect) * NSHeight(rect) / total;
    NSRect free = rect;
    NSUInteger start = 0, count = children.count;

    while (start < count && children[start].size > 0 && NSWidth(free) >= 1 && NSHeight(free) >= 1
           && _cells.count < kMaximumCells) {
        double side = MIN(NSWidth(free), NSHeight(free));
        double largest = children[start].size * areaPerByte;  // children are sorted largest first
        double rowArea = largest;
        double worst = WorstAspectRatio(largest, largest, rowArea, side);
        NSUInteger end = start + 1;
        while (end < count && children[end].size > 0) {
            double area = children[end].size * areaPerByte;
            double candidate = WorstAspectRatio(largest, area, rowArea + area, side);
            if (candidate > worst) break;
            worst = candidate;
            rowArea += area;
            end++;
        }

        BOOL isColumn = NSWidth(free) >= NSHeight(free);
        double thickness = rowArea / side;
        double offset = 0;
        for (NSUInteger i = start; i < end; i++) {
            double length = children[i].size * areaPerByte / thickness;
            NSRect cellRect = isColumn
                ? NSMakeRect(NSMinX(free), NSMinY(free) + offset, thickness, length)
                : NSMakeRect(NSMinX(free) + offset, NSMinY(free), length, thickness);
            offset += length;
            [self addCellForNode:children[i] rect:cellRect depth:depth branch:(depth == 0 ? (NSInteger)i : branch)];
        }

        if (isColumn) {
            free.origin.x += thickness;
            free.size.width -= thickness;
        } else {
            free.origin.y += thickness;
            free.size.height -= thickness;
        }
        start = end;
    }
}

- (void)addCellForNode:(FileNode *)node rect:(NSRect)rect depth:(NSInteger)depth branch:(NSInteger)branch {
    NSRect pixelRect = PixelAligned(rect);
    if (NSWidth(pixelRect) < 1 || NSHeight(pixelRect) < 1) return;

    TreemapCell *cell = [[TreemapCell alloc] init];
    cell.node = node;
    cell.rect = pixelRect;
    cell.color = CellColor(branch, depth, node.isFolder);
    [_cells addObject:cell];
    if (node.children.count == 0) return;

    // Leave a frame (and a name strip when there is room) so the folder stays visible around its contents.
    NSRect inner = NSInsetRect(pixelRect, 2, 2);
    if (NSWidth(pixelRect) >= 60 && NSHeight(pixelRect) >= 40) {
        cell.hasHeader = YES;
        inner = NSMakeRect(NSMinX(pixelRect) + 2, NSMinY(pixelRect) + kHeaderHeight,
                           NSWidth(pixelRect) - 4, NSHeight(pixelRect) - kHeaderHeight - 2);
    }
    NSUInteger cellCountBefore = _cells.count;
    [self layOutChildrenOf:node inRect:inner depth:depth + 1 branch:branch];
    cell.hasChildCells = _cells.count > cellCountBefore;
}

#pragma mark - Drawing

- (void)drawRect:(NSRect)dirtyRect {
    [self layOutCellsIfNeeded];
    [[NSColor controlBackgroundColor] setFill];
    NSRectFill(dirtyRect);

    if (_cells.count == 0) {
        [self drawPlaceholder];
        return;
    }

    static NSGradient *shine;
    if (!shine) {
        shine = [[NSGradient alloc] initWithColorsAndLocations:
                 [NSColor colorWithCalibratedWhite:1 alpha:0.30], 0.0,
                 [NSColor colorWithCalibratedWhite:1 alpha:0.0], 0.5,
                 [NSColor colorWithCalibratedWhite:0 alpha:0.15], 1.0, nil];
    }

    for (TreemapCell *cell in _cells) {
        if (!NSIntersectsRect(cell.rect, dirtyRect)) continue;
        [cell.color setFill];
        NSRectFill(cell.rect);
        if (!cell.node.isFolder && NSWidth(cell.rect) >= 4 && NSHeight(cell.rect) >= 4) {
            [shine drawInRect:cell.rect angle:45];
        }
        [[cell.color shadowWithLevel:0.4] setFill];
        NSFrameRectWithWidth(cell.rect, 1);
        [self drawLabelForCell:cell];
    }

    TreemapCell *hovered = [self cellForNode:_hoveredNode];
    if (hovered) {
        [[NSColor colorWithCalibratedWhite:1 alpha:0.8] setFill];
        NSFrameRectWithWidth(hovered.rect, 1);
    }
    TreemapCell *selected = [self cellForNode:self.selectedNode];
    if (selected) {
        [[NSColor blackColor] setFill];
        NSFrameRectWithWidth(selected.rect, 1);
        [[NSColor whiteColor] setFill];
        NSFrameRectWithWidth(NSInsetRect(selected.rect, 1, 1), 2);
    }
}

- (void)drawLabelForCell:(TreemapCell *)cell {
    NSRect rect = cell.rect;
    BOOL darkText = cell.color.brightnessComponent > 0.7;
    if (cell.hasHeader) {
        NSString *title = [NSString stringWithFormat:@"%@  %@", cell.node.name, FormatBytes(cell.node.size)];
        [title drawInRect:NSMakeRect(NSMinX(rect) + 4, NSMinY(rect) + 1, NSWidth(rect) - 8, kHeaderHeight - 2)
           withAttributes:[self labelAttributesBold:YES darkText:darkText]];
    } else if (!cell.hasChildCells && NSWidth(rect) >= 50 && NSHeight(rect) >= 30) {
        NSDictionary *attributes = [self labelAttributesBold:NO darkText:darkText];
        NSRect line = NSMakeRect(NSMinX(rect) + 4, NSMinY(rect) + 3, NSWidth(rect) - 8, 14);
        [cell.node.name drawInRect:line withAttributes:attributes];
        line.origin.y += 13;
        [FormatBytes(cell.node.size) drawInRect:line withAttributes:attributes];
    }
}

- (NSDictionary *)labelAttributesBold:(BOOL)bold darkText:(BOOL)darkText {
    static NSDictionary *cache[2][2];
    NSDictionary *attributes = cache[bold][darkText];
    if (!attributes) {
        NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
        style.lineBreakMode = NSLineBreakByTruncatingTail;
        NSColor *color = darkText ? [NSColor colorWithCalibratedWhite:0 alpha:0.85] : [NSColor whiteColor];
        NSFont *font = bold ? [NSFont boldSystemFontOfSize:10] : [NSFont systemFontOfSize:10];
        attributes = @{ NSFontAttributeName: font, NSForegroundColorAttributeName: color, NSParagraphStyleAttributeName: style };
        cache[bold][darkText] = attributes;
    }
    return attributes;
}

- (void)drawPlaceholder {
    NSString *message = self.focusNode ? @"This folder is empty." : self.placeholder;
    if (message.length == 0) return;
    NSDictionary *attributes = @{ NSFontAttributeName: [NSFont systemFontOfSize:15],
                                  NSForegroundColorAttributeName: [NSColor secondaryLabelColor] };
    NSSize size = [message sizeWithAttributes:attributes];
    [message drawAtPoint:NSMakePoint(NSMidX(self.bounds) - size.width / 2, NSMidY(self.bounds) - size.height / 2)
          withAttributes:attributes];
}

#pragma mark - Finding cells

/// The cell for node, or for its nearest ancestor when node itself is too small to be drawn.
- (TreemapCell *)cellForNode:(FileNode *)node {
    for (FileNode *candidate = node; candidate && candidate != self.focusNode; candidate = candidate.parent) {
        for (TreemapCell *cell in _cells) {
            if (cell.node == candidate) return cell;
        }
    }
    return nil;
}

- (FileNode *)nodeAtEvent:(NSEvent *)event {
    [self layOutCellsIfNeeded];
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    // Children come after their parents, so the last hit is the deepest one.
    for (TreemapCell *cell in _cells.reverseObjectEnumerator) {
        if (NSPointInRect(point, cell.rect)) return cell.node;
    }
    return nil;
}

#pragma mark - Mouse

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea *area in self.trackingAreas) [self removeTrackingArea:area];
    [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                      options:NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited
                                                              | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect
                                                        owner:self
                                                     userInfo:nil]];
}

- (void)mouseMoved:(NSEvent *)event {
    [self hoverNode:[self nodeAtEvent:event]];
}

- (void)mouseExited:(NSEvent *)event {
    [self hoverNode:nil];
}

- (void)hoverNode:(FileNode *)node {
    if (node == _hoveredNode) return;
    _hoveredNode = node;
    [self setNeedsDisplay:YES];
    [self.delegate treemapView:self didHoverNode:node];
}

- (void)mouseDown:(NSEvent *)event {
    FileNode *node = [self nodeAtEvent:event];
    if (!node) return;
    if (event.clickCount == 2) {
        [self.delegate treemapView:self didDoubleClickNode:node];
    } else {
        [self.delegate treemapView:self didClickNode:node];
    }
}

- (NSMenu *)menuForEvent:(NSEvent *)event {
    FileNode *node = [self nodeAtEvent:event];
    if (!node) return nil;
    [self.delegate treemapView:self didClickNode:node];
    return [self.delegate treemapView:self menuForNode:node];
}

@end
