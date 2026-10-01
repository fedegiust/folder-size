#import "PercentBarView.h"

@implementation PercentBarView

- (void)setFraction:(double)fraction {
    _fraction = MAX(0, MIN(1, fraction));
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    static NSDictionary *attributes;
    static CGFloat textWidth;
    if (!attributes) {
        NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
        style.alignment = NSTextAlignmentRight;
        attributes = @{ NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular],
                        NSForegroundColorAttributeName: [NSColor secondaryLabelColor],
                        NSParagraphStyleAttributeName: style };
        textWidth = [@"100.0 %" sizeWithAttributes:attributes].width;
    }

    NSRect bounds = self.bounds;
    NSRect textRect = NSMakeRect(NSMaxX(bounds) - textWidth - 4, NSMidY(bounds) - 7, textWidth, 14);
    [[NSString stringWithFormat:@"%.1f %%", self.fraction * 100] drawInRect:textRect withAttributes:attributes];

    NSRect track = NSMakeRect(NSMinX(bounds) + 2, NSMidY(bounds) - 4, NSMinX(textRect) - NSMinX(bounds) - 8, 8);
    if (NSWidth(track) < 10) return;
    [[NSColor colorWithCalibratedWhite:0.5 alpha:0.2] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:track xRadius:3 yRadius:3] fill];

    NSRect filled = track;
    filled.size.width = round(NSWidth(track) * self.fraction);
    if (NSWidth(filled) < 1) return;
    [[self barColor] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:filled xRadius:3 yRadius:3] fill];
}

- (NSColor *)barColor {
    if (@available(macOS 10.14, *)) {
        return [NSColor controlAccentColor];
    }
    return [NSColor alternateSelectedControlColor];
}

@end
