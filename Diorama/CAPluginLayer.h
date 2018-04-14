@import Cocoa;
@import QuartzCore;

@interface CAPluginLayer : CALayer

@property (copy) NSString *pluginGravity;
@property uint32_t pluginFlags;
@property uint64_t pluginId;
@property (copy) NSString *pluginType;

@end
