//
//  UIKitRenderer.swift
//  PortalView
//
//  Created by Guido Marucci Blas on 2/14/17.
//  Copyright © 2017 Guido Marucci Blas. All rights reserved.
//

import UIKit

public protocol ContainerController: class {

    var containerView: UIView { get }

    func attachChildController(_ controller: UIViewController)

    func registerDisposer(for identifier: String, disposer: @escaping () -> Void)

}

extension ContainerController where Self: UIViewController {

    public var containerView: UIView {
        return self.view
    }

    public func attachChildController(_ controller: UIViewController) {
        guard controller.parent == self else { return }

        controller.willMove(toParentViewController: self)
        self.addChildViewController(controller)
        controller.didMove(toParentViewController: self)
    }

}

public struct CustomComponentDescription {

    public let identifier: String
    public let information: [String : Any]
    public let style: StyleSheet<EmptyStyleSheet>
    public let layout: Layout

}

public protocol UIKitCustomComponentRenderer {

    associatedtype MessageType
    associatedtype RouteType: Route

    init(container: ContainerController)

    func renderComponent(
        _ componentDescription: CustomComponentDescription,
        inside view: UIView,
        dispatcher: @escaping (Action<RouteType, MessageType>) -> Void)

}

public struct VoidCustomComponentRenderer<MessageType, RouteType: Route>: UIKitCustomComponentRenderer {

    public init(container: ContainerController) {

    }

    public func renderComponent(
        _ componentDescription: CustomComponentDescription,
        inside view: UIView,
        dispatcher: @escaping (Action<RouteType, MessageType>) -> Void) {

    }
}

public struct UIKitComponentRenderer<
    MessageType,
    RouteType,
    CustomComponentRendererType: UIKitCustomComponentRenderer
    >: Renderer

    where CustomComponentRendererType.MessageType == MessageType, CustomComponentRendererType.RouteType == RouteType {

    public typealias CustomComponentRendererFactory = () -> CustomComponentRendererType
    public typealias ActionType = Action<RouteType, MessageType>

    public var isDebugModeEnabled: Bool = false

    internal let layoutEngine: LayoutEngine
    internal let rendererFactory: CustomComponentRendererFactory

    private let containerView: UIView

    public init(
        containerView: UIView,
        layoutEngine: LayoutEngine = YogaLayoutEngine(),
        rendererFactory: @escaping CustomComponentRendererFactory) {
        self.containerView = containerView
        self.rendererFactory = rendererFactory
        self.layoutEngine = layoutEngine
    }

    public func render(component: Component<ActionType>) -> Mailbox<ActionType> {
        containerView.subviews.forEach { $0.removeFromSuperview() }
        let renderer = ComponentRenderer(component: component, rendererFactory: rendererFactory)
        let renderResult = renderer.render(with: layoutEngine, isDebugModeEnabled: isDebugModeEnabled)
        renderResult.view.managedByPortal = true
        layoutEngine.layout(view: renderResult.view, inside: containerView)
        renderResult.afterLayout?()

        if isDebugModeEnabled {
            renderResult.view.safeTraverse { $0.addDebugFrame() }
        }

        return renderResult.mailbox ?? Mailbox<ActionType>()
    }

}

internal typealias AfterLayoutTask = () -> Void

internal struct Render<MessageType> {

    let view: UIView
    let mailbox: Mailbox<MessageType>?
    let afterLayout: AfterLayoutTask?

    init(view: UIView,
         mailbox: Mailbox<MessageType>? = .none,
         executeAfterLayout afterLayout: AfterLayoutTask? = .none) {
        self.view = view
        self.afterLayout = afterLayout
        self.mailbox = mailbox
    }

}

internal protocol UIKitRenderer {
    associatedtype MessageType
    associatedtype RouteType: Route

    func render(with layoutEngine: LayoutEngine, isDebugModeEnabled: Bool) -> Render<Action<RouteType, MessageType>>

}

extension UIView {

    internal func apply(changeSet: [BaseStyleSheet.Property]) {
        for property in changeSet {
            switch property {

            case .alpha(let alpha):
                alpha |> { self.alpha = CGFloat($0) }

            case .backgroundColor(let backgroundColor):
                backgroundColor |> { self.backgroundColor = $0.asUIColor }

            case .cornerRadius(let cornerRadius):
                cornerRadius |> { self.layer.cornerRadius = CGFloat($0) }

            case .borderColor(let borderColor):
                borderColor |> { self.layer.borderColor = $0.asUIColor.cgColor }

            case .borderWidth(let borderWidth):
                borderWidth |> { self.layer.borderWidth = CGFloat($0) }

            case .contentMode(let contentMode):
                contentMode |> { self.contentMode = $0.toUIViewContentMode }

            case .clipToBounds(let clipToBounds):
                clipToBounds |> { self.clipsToBounds = $0 }

            case .shadow(let shadowChangeSet):
                self.layer.apply(changeSet: shadowChangeSet)
            }
        }
    }

    internal func apply(style: BaseStyleSheet) {
        style.backgroundColor   |> { self.backgroundColor = $0.asUIColor }
        style.cornerRadius      |> { self.layer.cornerRadius = CGFloat($0) }
        style.borderColor       |> { self.layer.borderColor = $0.asUIColor.cgColor }
        style.borderWidth       |> { self.layer.borderWidth = CGFloat($0) }
        style.alpha             |> { self.alpha = CGFloat($0) }
        style.contentMode       |> { self.contentMode = $0.toUIViewContentMode }
        style.clipToBounds      |> { self.clipsToBounds = $0 }
        style.shadow            |> { shadow in
            self.layer.shadowColor = shadow.color.asUIColor.cgColor
            self.layer.shadowOpacity = shadow.opacity
            self.layer.shadowOffset = shadow.offset.asCGSize
            self.layer.shadowRadius = CGFloat(shadow.radius)
            self.layer.shouldRasterize = shadow.shouldRasterize
        }

    }

}

fileprivate let defaultLayer = CALayer()

fileprivate extension CALayer {

    fileprivate func apply(changeSet: [Shadow.Property]?) {
        if let changeSet = changeSet {
            for property in changeSet {
                switch property {

                case .color(let shadowColor):
                    self.shadowColor = shadowColor.asUIColor.cgColor

                case .opacity(let shadowOpacity):
                    self.shadowOpacity = shadowOpacity

                case .offset(let shadowOffset):
                    self.shadowOffset = shadowOffset.asCGSize

                case .radius(let shadowRadius):
                    self.shadowRadius = CGFloat(shadowRadius)

                case .shouldRasterize(let shouldRasterize):
                    self.shouldRasterize = shouldRasterize

                }
            }
        } else {
            self.shadowColor = defaultLayer.shadowColor
            self.shadowOpacity = defaultLayer.shadowOpacity
            self.shadowOffset = defaultLayer.shadowOffset
            self.shadowRadius = defaultLayer.shadowRadius
            self.shouldRasterize = defaultLayer.shouldRasterize
        }
    }

}

fileprivate extension ContentMode {

    var toUIViewContentMode: UIViewContentMode {
        switch self {

        case .scaleToFill:
            return UIViewContentMode.scaleToFill

        case .scaleAspectFill:
            return UIViewContentMode.scaleAspectFill

        case .scaleAspectFit:
            return UIViewContentMode.scaleAspectFit

        }
    }

}

extension SupportedOrientations {

    var uiInterfaceOrientation: UIInterfaceOrientationMask {
        switch self {
        case .all:
            return .all
        case .landscape:
            return .landscape
        case .portrait:
            return .portrait
        }
    }

}

extension Offset {

    internal var asCGSize: CGSize {
        return CGSize(width: CGFloat(x), height: CGFloat(y))
    }

}
