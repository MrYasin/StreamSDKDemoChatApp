//
//  Keyboard.swift
//  StreamChat
//
//  Created by Alexey Bukhtin on 04/06/2019.
//  Copyright © 2019 Stream.io Inc. All rights reserved.
//

import UIKit
import RxCocoa
import RxSwift
import RxGesture

struct Keyboard {
    
    static let shared = Self()
    let notification: Driver<KeyboardNotification>
    
    init() {
        let keyboardNotifications: Observable<KeyboardNotification> =
            Observable.merge(NotificationCenter.default.rx.notification(UIResponder.keyboardWillChangeFrameNotification),
                             NotificationCenter.default.rx.notification(UIResponder.keyboardWillHideNotification),
                             NotificationCenter.default.rx.notification(UIResponder.keyboardWillShowNotification))
                .map { KeyboardNotification($0) }
        
        let windowPan: Observable<KeyboardNotification> =
            NotificationCenter.default.rx.notification(UIApplication.didFinishLaunchingNotification)
            .void()
            .startWith(Void())
            .flatMapLatest({ _ -> Observable<UIPanGestureRecognizer> in
                guard let window = UIApplication.shared.windows.first else {
                    return .empty()
                }
                
                return window.rx.panGesture().when(.began, .changed, .ended)
            })
            .withLatestFrom(keyboardNotifications) { ($0, $1) }
            .filter { $1.height > 0 }
            .compactMap { KeyboardNotification(panGesture: $0, with: $1) }
        
        notification = Observable.merge(windowPan, keyboardNotifications)
            .distinctUntilChanged()
            .asDriver(onErrorJustReturn: KeyboardNotification(.init(name: UIResponder.keyboardWillChangeFrameNotification)))
    }
}

struct KeyboardNotification: Equatable {
    struct Animation: Equatable {
        let curve: UIView.AnimationOptions
        let duration: TimeInterval
        
        init?(_ notification: Notification) {
            guard let userInfo = notification.userInfo,
                let curve = (userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.uintValue,
                let duration = (userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue,
                curve > 0,
                duration > 0 else {
                    return nil
            }
            
            self.curve = UIView.AnimationOptions(rawValue: curve)
            self.duration = duration
        }
        
        static func == (lhs: Animation, rhs: Animation) -> Bool {
            return lhs.curve == rhs.curve && lhs.duration == rhs.duration
        }
    }
    
    let frame: CGRect?
    let animation: Animation?
    
    var height: CGFloat {
        if let frame = frame {
            return UIScreen.main.bounds.height - frame.origin.y
        }
        
        return 0
    }
    
    var isVisible: Bool {
        return height > 0
    }
    
    var isHidden: Bool {
        return !isVisible
    }
    
    init(_ notification: Notification) {
        if let frame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue {
            if frame.origin.y < 0 {
                var newFrame = frame
                newFrame.origin.y = UIScreen.main.bounds.height - newFrame.height
                self.frame = newFrame
            } else {
                self.frame = frame
            }
        } else {
            frame = nil
        }
        
        animation = Animation(notification)
    }
    
    init?(panGesture: UIPanGestureRecognizer, with keyboardNotification: KeyboardNotification) {
        guard let frame = keyboardNotification.frame else {
            return nil
        }
        
        guard case .changed = panGesture.state,
            let window = UIApplication.shared.windows.first,
            frame.origin.y < UIScreen.main.bounds.height else {
                return nil
                
        }
        
        let origin = panGesture.location(in: window)
        var newFrame = frame
        newFrame.origin.y = max(origin.y, UIScreen.main.bounds.height - frame.height)
        
        self.frame = newFrame
        animation = nil
    }
    
    static func == (lhs: KeyboardNotification, rhs: KeyboardNotification) -> Bool {
        return lhs.frame == rhs.frame && lhs.animation == rhs.animation
    }
}
