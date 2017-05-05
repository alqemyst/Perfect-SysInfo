//
//  PerfectSysInfo.swift
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
#if os(Linux)
import SwiftGlibc
#else
import Darwin
#endif

extension String {

  internal var trimmed: String {
    var buf = [UInt8]()
    var trimming = true
    for c in self.utf8 {
      if trimming && c < 33 { continue }
      trimming = false
      buf.append(c)
    }//end ltrim
    while let last = buf.last, last < 33 {
      buf.removeLast()
    }//end rtrim
    buf.append(0)
    return String(cString: buf)
  }//end trim

  /// split a string into an array of lines
  internal var asLines: [String] {
    get {
      return self.utf8
        .split(separator: 10)
        .filter { $0.count > 0 }
        .map { String(describing: $0) }
    }
  }

  /// a quick buffer size definition
  internal static let szSTR = 4096

  /// treat the string as a file name and get the content by this name,
  /// will return nil if failed
  internal var asFile: String? {
    get {
      guard let f = fopen(self, "r") else { return nil }
      var content = [Int8]()
      let buf = UnsafeMutablePointer<Int8>.allocate(capacity: String.szSTR)
      memset(buf, 0, String.szSTR)
      var count = 0
      repeat {
        count = fread(buf, 1, String.szSTR, f)
        if count > 0 {
          let buffer = UnsafeBufferPointer(start: buf, count: count)
          content += Array(buffer)
        }//end if
      }while(count > 0)
      fclose(f)
      buf.deallocate(capacity: String.szSTR)
      let ret = String(cString: content)
      return ret
    }
  }
  /// equivalent to hasPrefix
  /// - parameters: 
  ///   - prefix: the prefix string to looking for
  /// - returns: 
  ///   true if the string has such a prefix
  internal func match(prefix: String) -> Bool {
    if prefix == self { return true }
    guard prefix.utf8.count > 0,
      self.utf8.count > prefix.utf8.count,
      let str = strdup(self) else {
        return false
    }//end str
    str.advanced(by: prefix.utf8.count).pointee = 0
    let matched = strcmp(str, prefix) == 0
    free(str)
    return matched
  }//end match

  /// translate a labeless / space delimited string into a dictionry with the given definition
  /// - parameters: 
  ///   - definition: an array for the expected string definition, each element is a name/type pair, which type only means string or non-string simply because only string needs quote in output
  /// - returns: dictionary
  internal func parse(definition: [(keyName: String, isString: Bool )]) -> [String: String] {
    let values = self.utf8.split(separator: 32).map { String($0) ?? "" }.filter { !$0.isEmpty }
    let size = min(values.count, definition.count)
    guard size > 0 else { return [:] }
    var content: [String: String] = [:]
    for i in 0 ... size - 1 {
      let key = definition[i].keyName
      let value = values[i]
      content[key] = value
    }//next i
    return content
  }
}

public class SysInfo {

  /// return total traffic summary from all interfaces, 
  /// i for receiving and o for transmitting, both in KB
  public static var Net: (i: Int, o: Int)? {
    get {
      var io = (i: 0, o: 0)
      #if os(Linux)
        guard let content = "/proc/net/dev".asFile else { return nil }
        content.asLines.map { line -> String in
          if let column = strchr(line, 58) {
            return String(cString: column.advanced(by: 1))
          } else {
            return ""
          }
          }.filter { !$0.isEmpty } .forEach { line in
            guard let str = strdup(line) else { return }
            var numbers = [Int]()
            let delimiter = " \t\n\r"
            var token = strtok(str, delimiter)
            while let tok = token {
              numbers.append(Int(String(cString: tok)) ?? 0)
              token = strtok(nil, delimiter)
            }//end while
            free(str)
            if numbers.count < 9 { return }
            io.i += numbers[0]
            io.o += numbers[8]
        }
      #else
        var mib = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2]
        let NULL = UnsafeMutableRawPointer(bitPattern: 0)
        guard (mib.withUnsafeMutableBufferPointer { ptr -> Bool in
          var len = 0
          guard 0 == sysctl(ptr.baseAddress, 6, NULL, &len, NULL, 0)
            else { return false }

          let buf = UnsafeMutablePointer<Int8>.allocate(capacity: len)
          if 0 == sysctl(ptr.baseAddress, 6, buf, &len, NULL, 0) {
            var cursor = 0
            repeat {
              cursor = buf.advanced(by: cursor).withMemoryRebound(to: if_msghdr.self, capacity: MemoryLayout<if_msghdr>.size) { pIfm -> Int in
                let ifm = pIfm.pointee
                cursor += Int(ifm.ifm_msglen)
                if integer_t(ifm.ifm_type) == RTM_IFINFO2 {
                  pIfm.withMemoryRebound(to: if_msghdr2.self, capacity: MemoryLayout<if_msghdr2>.size) { pIfm2 in
                    io.i += Int(pIfm2.pointee.ifm_data.ifi_ibytes)
                    io.0 += Int(pIfm2.pointee.ifm_data.ifi_obytes)
                  }//end ifm2
                }//end if
                return cursor
              }//end bound
            } while (cursor < len)
            buf.deallocate(capacity: len)
          }//end if
          return true
        }) else {
          return nil
        }//end buf
      #endif
      return (i: io.i / 1024, o: io.o / 1024)
    }
  }

  /// return physical CPU information
  public static var CPU: [String: [String: Int]] {
    get {
    #if os(Linux)
      let definition: [(keyName: String, isString: Bool)]
        = [("name", true),
           ("user", false), ("nice", false),
           ("system", false), ("idle", false)]
      guard let content = "/proc/stat".asFile else { return [:] }
      let array = content.asLines.filter { $0.match(prefix: "cpu") }
        .map { $0.parse(definition: definition) }
      var lines: [String: [String: Int]] = [:]
      for item in array {
        guard let title = item["name"] else { continue }
        var stat: [String: Int] = [:]
        for (k,v) in (item.filter { $0.key != "name" }) {
          stat[k] = Int(v) ?? 0
        }//next
        lines[title] = stat
      }//next
    #else
      var pCPULoadArray = processor_info_array_t(bitPattern: 0)
      var processorMsgCount = mach_msg_type_name_t()
      var processorCount = natural_t()
      var totalUser = 0
      var totalIdle = 0
      var totalSystem = 0
      var totalNice = 0
      guard 0 == host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &processorCount, &pCPULoadArray, &processorMsgCount),
      let cpuLoadArray = pCPULoadArray
        else { return [:] }
      //print(CPU_STATE_MAX, CPU_STATE_IDLE, CPU_STATE_NICE, CPU_STATE_USER, CPU_STATE_SYSTEM)
      //4 2 3 0 1
      let cpuLoad = cpuLoadArray.withMemoryRebound(
        to: processor_cpu_load_info.self,
        capacity: Int(processorCount) * MemoryLayout<processor_cpu_load_info>.size)
        {
          ptr -> processor_cpu_load_info_t in
          return ptr
      }
      var lines: [String:[String:Int]] = [:]
      let count = Int(processorCount)
      for i in 0 ... count - 1 {
        let user = Int(cpuLoad[i].cpu_ticks.0)
        let system = Int(cpuLoad[i].cpu_ticks.1)
        let idle = Int(cpuLoad[i].cpu_ticks.2)
        let nice = Int(cpuLoad[i].cpu_ticks.3)
        lines["cpu\(i)"] = ["user": user, "system": system, "idle": idle, "nice": nice]
        totalUser += user
        totalSystem += system
        totalIdle += idle
        totalNice += nice
      }//next
      munmap(cpuLoadArray, Int(vm_page_size))
      totalUser /= count
      totalSystem /= count
      totalIdle /= count
      totalNice /= count
      lines["cpu"] = ["user": totalUser, "system": totalSystem, "idle": totalIdle, "nice": totalNice]
    #endif
      return lines
    }
  }

  /// return Metrics of Physical Memory, each counter in Megabytes
  public static var Memory: [String: Int] {
    get {
      #if os(Linux)
        guard let content = "/proc/meminfo".asFile else { return [:] }
        var stat:[String: Int] = [:]
        content.utf8.split(separator: 10).forEach { line in
          let lines = line.split(separator: 58).map { String(describing: $0) }
          let key = lines[0]
          guard lines.count > 1, let str = strdup(lines[1]) else { return }
          if let kb = strstr(str, "kB") {
            kb.pointee = 0
          }//end if
          let value = String(cString: str).trimmed
          stat[key] = (Int(value) ?? 0) / 1024
          free(str)
        }
        return stat
      #else
        let size = MemoryLayout<vm_statistics>.size / MemoryLayout<integer_t>.size
        let pStat = UnsafeMutablePointer<integer_t>.allocate(capacity: size)
        var stat: [String: Int] = [:]
        var count = mach_msg_type_number_t(size)
        if 0 == host_statistics(mach_host_self(), HOST_VM_INFO, pStat, &count){
          let array = Array(UnsafeBufferPointer(start: pStat, count: size))
          let tags = ["free", "active", "inactive", "wired", "zero_filled", "reactivations", "pageins", "pageouts", "faults", "cow", "lookups", "hits"]
          let cnt = min(tags.count, array.count)
          for i in 0 ... cnt - 1 {
            let key = tags[i]
            let value = array[i]
            stat[key] = Int(value) / 256
          }//next i
        }//end if
        pStat.deallocate(capacity: size)
        return stat
      #endif
    }//end get
  }//end var
}
