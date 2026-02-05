//
//  TransferTaskEntity+CoreDataProperties.swift
//  
//
//  Created by HLJY on 2026/2/4.
//
//  This file was automatically generated and should not be edited.
//

import Foundation
import CoreData


extension TransferTaskEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<TransferTaskEntity> {
        return NSFetchRequest<TransferTaskEntity>(entityName: "TransferTaskEntity")
    }

    @NSManaged public var fileName: String?
    @NSManaged public var fileSize: Int64
    @NSManaged public var fileUrl: Data?
    @NSManaged public var md5: String?
    @NSManaged public var progress: Double
    @NSManaged public var status: String?
    @NSManaged public var targetDirId: Int64
    @NSManaged public var taskId: String?
    @NSManaged public var timestamp: Date?
    @NSManaged public var uploadedBytes: Int64
    @NSManaged public var userId: Int32

}

extension TransferTaskEntity : Identifiable {

}
