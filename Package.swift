// swift-tools-version:5.2
// The swift-tools-version declares the minimum version of Swift required to build this package.
//
//  Package.swift
//  Perfect SysInfo
//
//  Created by Rockford Wei on May 3rd, 2017.
//	Copyright (C) 2017 PerfectlySoft, Inc.
//
//===----------------------------------------------------------------------===//
//
// This source file is part of the Perfect.org open source project
//
// Copyright (c) 2017 - 2018 PerfectlySoft Inc. and the Perfect project authors
// Licensed under Apache License v2.0
//
// See http://perfect.org/licensing.html for license information
//
//===----------------------------------------------------------------------===//
//

import PackageDescription

let package = Package(
	name: "perfect-sysinfo",
	platforms: [
		.macOS(.v10_15)
	],
	products: [
		.library(name: "PerfectSysInfo", targets: ["PerfectSysInfo"]),
	],
	dependencies: [ ],
	targets: [
		.target(name: "PerfectSysInfo", dependencies: []),
		.testTarget(name: "PerfectSysInfoTests", dependencies: ["PerfectSysInfo"]),
	]
)
