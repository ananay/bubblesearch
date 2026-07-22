//
//  TitlebarSparkleUserDriverDelegate.swift
//  BubbleSearch
//
//  Created by Vishrut Jha on 7/22/26.
//

import Sparkle

@MainActor
protocol TitlebarSparkleUserDriverDelegate: AnyObject {
    func userDriverDidRequestPermission(reply: @escaping (SUUpdatePermissionResponse) -> Void)
    func userDriverDidStartCheck(cancellation: @escaping () -> Void)
    func userDriverDidFindUpdate(
        _ offer: SparkleUpdateOffer,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    )
    func userDriverDidFindBackgroundUpdate(_ offer: SparkleUpdateOffer)
    func userDriverDidChangeProgress(_ status: SparkleUpdateStatus, cancellation: (() -> Void)?)
    func userDriverNeedsChoice(
        for status: SparkleUpdateStatus,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    )
    func userDriverIsReadyToInstallOnQuit(
        _ offer: SparkleUpdateOffer,
        install: @escaping () -> Void
    )
    func userDriverDidStartInstalling(applicationTerminated: Bool, retry: @escaping () -> Void)
    func userDriverDidFinish(message: String, isError: Bool)
    func userDriverDidRequestFocus()
    func userDriverDidDismissUpdate()
}
