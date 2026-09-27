//
//  ObserverPattern.swift
//  TobyTunes
//
//  Created by Toby Nelson on 06/08/2016.
//  Copyright © 2016 Agent Lobster. All rights reserved.
//

import Foundation

protocol Observer: AnyObject {
    var subscribers: [Subscriber] {get set}

    func propertyChanged(propertyName: String, newValue: Double, options: [String:String]?)

    func subscribe(subscriber: Subscriber)

    func unsubscribe(subscriber: Subscriber)
}

protocol Subscriber: AnyObject {
    var properties : [String] {get set}
    func notify(propertyValue: String, newValue: Double, options: [String:String]?)
}
