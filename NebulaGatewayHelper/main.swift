// main.swift
// NebulaGatewayHelper

import Foundation

let helper = HelperTool()
let listener = NSXPCListener(machServiceName: "com.nebulagateway.helper")
listener.delegate = helper
listener.resume()

RunLoop.current.run()
