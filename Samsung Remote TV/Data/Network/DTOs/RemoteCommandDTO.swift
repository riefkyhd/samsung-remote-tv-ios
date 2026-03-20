import Foundation

struct RemoteCommandDTO: Codable, Sendable {
    struct Parameters: Codable, Sendable {
        let Cmd: String
        let DataOfCmd: String
        let Option: String
        let TypeOfRemote: String
    }

    let method: String
    let params: Parameters

    static func key(_ key: RemoteKey, command: String) -> RemoteCommandDTO {
        RemoteCommandDTO(
            method: "ms.remote.control",
            params: Parameters(
                Cmd: command,
                DataOfCmd: key.rawValue,
                Option: "false",
                TypeOfRemote: "SendRemoteKey"
            )
        )
    }
}

struct AppLaunchCommandDTO: Codable, Sendable {
    struct Parameters: Codable, Sendable {
        struct LaunchData: Codable, Sendable {
            let appId: String
            let action_type: String
        }

        let event: String
        let to: String
        let data: LaunchData
    }

    let method: String
    let params: Parameters

    static func launch(appId: String) -> AppLaunchCommandDTO {
        AppLaunchCommandDTO(
            method: "ms.channel.emit",
            params: Parameters(
                event: "ed.apps.launch",
                to: "host",
                data: Parameters.LaunchData(appId: appId, action_type: "DEEP_LINK")
            )
        )
    }
}
