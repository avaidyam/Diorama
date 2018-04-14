import Cocoa

public struct WindowData {
    public let name: String
    public let pid: Int
    public let wid: Int
    public let layer: Int
    public let opacity: CGFloat
    public let frame: CGRect
}

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    
    @IBOutlet weak var window: NSWindow!
    private var rootLayer: CALayer!
    private var space = CGSSpace(level: 1)
    
    private var layers: [Int: CAPluginLayer] = [:]
    private var windows: [WindowData] = [] {
        didSet {
            self.diff(oldValue, self.windows)
        }
    }
    
    func applicationWillFinishLaunching(_ aNotification: Notification) {
        self.rootLayer = self.window.contentView!.layer
        self.window.aspectRatio = NSSize(width: 16, height: 10)
        self.window.isMovable = true
        self.window.isMovableByWindowBackground = true
        self.space.windows.insert(self.window)
        self.refresh()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        self.space.windows.removeAll()
    }
    
    private func refresh() {
        let data = CGWindowListCopyWindowInfo([.optionOnScreenOnly], CGWindowID(0)) as? [[String: AnyObject]]
        
        // also, preserves the decreasing z-order!
        var q = [WindowData]()
        for d in (data ?? []) {
            
            // don't include our own window!
            guard   let _id = d[kCGWindowNumber as String] as? Int,
                _id != self.window.windowNumber
                else { continue }
            
            let _r = d[kCGWindowBounds as String] as? [String: Int]
            let rect = NSRect(x: _r?["X"] ?? 0, y: _r?["Y"] ?? 0,
                              width: _r?["Width"] ?? 0, height: _r?["Height"] ?? 0)
            
            let window = WindowData(
                name: d[kCGWindowName as String] as? String ?? "",
                pid: d[kCGWindowOwnerPID as String] as? Int ?? -1,
                wid: d[kCGWindowNumber as String] as? Int ?? -1,
                layer: d[kCGWindowLayer as String] as? Int ?? 0,
                opacity: d[kCGWindowAlpha as String] as? CGFloat ?? 0.0,
                frame: rect
            )
            q.append(window)
        }
        self.windows = q
        
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + .milliseconds(250)) {
            self.refresh()
        }
    }
    
    private func diff(_ oldValue: [WindowData], _ newValue: [WindowData]) {
        var added = Set<Int>()
        for x in (newValue.map { $0.wid }) where !(oldValue.map { $0.wid }).contains(x) {
            added.insert(x)
        }
        
        var removed = Set<Int>()
        for x in (oldValue.map { $0.wid }) where !(newValue.map { $0.wid }).contains(x) {
            removed.insert(x)
        }
        
        var same = Set<Int>()
        for x in (newValue.map { $0.wid }) where (oldValue.map { $0.wid }).contains(x) {
            same.insert(x)
        }
        
        //
        //
        //
        
        CATransaction.begin()
        
        // remove closed windows
        for x in removed {
            let layer = self.layers[x]
            layer?.removeFromSuperlayer()
            self.layers[x] = nil
        }
        
        // add any new windows
        for x in added {
            let win = newValue.first { $0.wid == x }!
            
            let layer = CAPluginLayer()
            layer.pluginType = "com.apple.WindowServer.CGSWindow"
            layer.pluginId = UInt64(win.wid)
            layer.pluginGravity = kCAGravityResizeAspect
            layer.pluginFlags = 0x0 //shadow
            self.rootLayer.addSublayer(layer)
            
            self.layers[x] = layer
        }
        
        // update frames for all same + new windows
        for x in same.union(added) {
            let win = newValue.first { $0.wid == x }!
            let layer = self.layers[x]
            
            var rect = win.frame
            rect.origin.y = NSScreen.main!.frame.height - rect.maxY // flipped
            
            let aspectWidth = self.rootLayer.frame.width / NSScreen.main!.frame.width
            let aspectHeight = self.rootLayer.frame.height / NSScreen.main!.frame.height
            let scaled = CGRect(x: aspectWidth * rect.minX, y: aspectHeight * rect.minY,
                                width: aspectWidth * rect.width, height: aspectHeight * rect.height)
            layer?.frame = scaled
            layer?.opacity = Float(win.opacity)
        }
        
        // since WindowServer gives us the window list in decreasing z-order,
        // preserve that order and set that onto the layers.
        for (idx, x) in newValue.enumerated() {
            let layer = self.layers[x.wid]
            layer?.zPosition = CGFloat(newValue.count - idx)
        }
        CATransaction.commit()
        CATransaction.flush()
    }
}

/// Small Spaces API wrapper.
public final class CGSSpace {
    private let identifier: CGSSpaceID
    
    public var windows: Set<NSWindow> = [] {
        didSet {
            let remove = oldValue.subtracting(self.windows)
            let add = self.windows.subtracting(oldValue)
            
            CGSRemoveWindowsFromSpaces(_CGSDefaultConnection(),
                                       remove.map { $0.windowNumber } as NSArray,
                                       [self.identifier])
            CGSAddWindowsToSpaces(_CGSDefaultConnection(),
                                  add.map { $0.windowNumber } as NSArray,
                                  [self.identifier])
        }
    }
    
    /// Initialized `CGSSpace`s *MUST* be de-initialized upon app exit!
    public init(level: Int = 0) {
        let flag = 0x1 // this value MUST be 1, otherwise, Finder decides to draw desktop icons
        self.identifier = CGSSpaceCreate(_CGSDefaultConnection(), flag, nil)
        CGSSpaceSetAbsoluteLevel(_CGSDefaultConnection(), self.identifier, level/*400=facetime?*/)
        CGSShowSpaces(_CGSDefaultConnection(), [self.identifier])
        
    }
    
    deinit {
        CGSHideSpaces(_CGSDefaultConnection(), [self.identifier])
        CGSSpaceDestroy(_CGSDefaultConnection(), self.identifier)
    }
}

// CGSSpace stuff:
fileprivate typealias CGSConnectionID = UInt
fileprivate typealias CGSSpaceID = UInt64
@_silgen_name("_CGSDefaultConnection")
fileprivate func _CGSDefaultConnection() -> CGSConnectionID
@_silgen_name("CGSSpaceCreate")
fileprivate func CGSSpaceCreate(_ cid: CGSConnectionID, _ unknown: Int, _ options: NSDictionary?) -> CGSSpaceID
@_silgen_name("CGSSpaceDestroy")
fileprivate func CGSSpaceDestroy(_ cid: CGSConnectionID, _ space: CGSSpaceID)
@_silgen_name("CGSSpaceSetAbsoluteLevel")
fileprivate func CGSSpaceSetAbsoluteLevel(_ cid: CGSConnectionID, _ space: CGSSpaceID, _ level: Int)
@_silgen_name("CGSAddWindowsToSpaces")
fileprivate func CGSAddWindowsToSpaces(_ cid: CGSConnectionID, _ windows: NSArray, _ spaces: NSArray)
@_silgen_name("CGSRemoveWindowsFromSpaces")
fileprivate func CGSRemoveWindowsFromSpaces(_ cid: CGSConnectionID, _ windows: NSArray, _ spaces: NSArray)
@_silgen_name("CGSHideSpaces")
fileprivate func CGSHideSpaces(_ cid: CGSConnectionID, _ spaces: NSArray)
@_silgen_name("CGSShowSpaces")
fileprivate func CGSShowSpaces(_ cid: CGSConnectionID, _ spaces: NSArray)
