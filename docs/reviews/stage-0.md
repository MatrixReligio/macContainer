# Stage 0: Apple container 1.1.0 contract review

- Review date: 2026-07-16
- Upstream: `apple/container` tag `1.1.0`
- Upstream commit: `5973b9cc626a3e7a499bb316a958237ebe14e2ed`
- Gate: PASS

## Verification result

The local SwiftPM checkout resolves to the exact tag commit above. The reviewed
command reference contains 61 command headings, the acceptance matrix contains
61 unique operation IDs, and the bundled contract contains the same 61 IDs and
352 operation-scoped parameter slots. No missing or extra operation or parameter
ID was found.

Commands and observed results:

```text
swift test --filter ContractRepositoryTests
PASS: 5 Swift Testing tests

swift scripts/check-contract-coverage.swift \
  Config/contracts/apple-container-1.1.0-acceptance.json \
  Sources/MCContracts/Resources/apple-container-1.1.0.json
PASS: apple/container 1.1.0, 61 operations, 0 missing, 0 extra

rg -n 'TODO|TBD|implement later|similar to' \
  Config/contracts Sources/MCContracts Tests/MCContractsTests
PASS: exit 1, no matches
```

The command reference SHA-256 is
`105f5c0dbf3f392fc3708b060e92a17dc20fa99e37591bc344687a6edb0eccba`.
The two expanded shared-flag sources are:

| Source | SHA-256 |
| --- | --- |
| `Sources/Services/ContainerAPIService/Client/Flags.swift` | `7b1504cd07f4bb9870fc90a73595254a15fbaf17374c654537ced183577ba52a` |
| `Sources/Services/MachineAPIService/Client/Flags.swift` | `55c80124d75572960bdf13d309ffa5b53b4ce95078b931408a736500c395e5bd` |

## Review method and reconciliations

Every acceptance entry was checked against its exact source file, expanding
`@OptionGroup` definitions from the shared sources and comparing
`@Argument`, `@Option`, and `@Flag` declarations with the tagged command
reference. Native actions were then checked against the direct client or service
call made by the source.

The apparent documentation-count differences were resolved from source:

- `core.build` has hidden `--cache-in` and `--cache-out` options; both affect
  the build and remain in the contract.
- `containers.exec` and `machines.run` inherit the shared `--ulimit`
  parser entry even though the generated 1.1.0 command reference omits it.
  The contract retains the accepted upstream input so later bridge tests can
  explicitly prove behavior rather than silently lose it.
- `registries.login.password` represents Apple's secure prompt/standard-input
  credential path. It is a secure native input, not a literal command option.
- Hidden progress flags on machine stop/delete are retained as upstream
  evidence, but their terminal presentation is replaced by the native Activity
  Center.
- Volume driver settings and machine setting keys are accepted values within
  `driverOptions` and `settings`; they are not separate top-level parameters.

No mismatch required changing the acceptance matrix or bundled contract.

## Counts by domain

“Slots” counts every operation-scoped occurrence, while “unique parameters”
deduplicates stable parameter IDs inside a domain.

| Domain | Operations | Parameter slots | Unique parameters |
| --- | ---: | ---: | ---: |
| builder | 4 | 13 | 10 |
| configuration | 1 | 2 | 2 |
| containers | 13 | 99 | 63 |
| core | 2 | 73 | 64 |
| dns | 3 | 8 | 5 |
| images | 9 | 39 | 19 |
| kernel | 1 | 6 | 6 |
| machines | 9 | 52 | 36 |
| networks | 5 | 17 | 13 |
| registries | 3 | 11 | 8 |
| system | 6 | 18 | 10 |
| volumes | 5 | 14 | 9 |
| **Total** | **61** | **352** | — |

Risk review also yielded 23 read-only, 22 mutating, 11 destructive, and 5
privileged operations.

## Native rendering decisions

Rendering-only CLI inputs remain traceable in the contract but do not become
terminal-oriented controls:

- `format` occurs in 13 operations and maps to native tables plus explicit
  JSON/YAML/TOML export choices where upstream supports them.
- `quiet` occurs in 9 operations and maps to native compact/result visibility,
  not suppression of safety or error information.
- `progressStyle` occurs in 7 operations and maps to native Activity Center
  progress; ANSI/TTY styling is never emitted into SwiftUI.
- `debug` occurs in all 61 operations and maps to the redacted diagnostics
  policy, not an arbitrary CLI execution path.
- `configuration.manage` represents the typed configuration view and native
  export action required by the product specification.

These mappings preserve result-affecting options while replacing terminal-only
presentation semantics with accessible macOS behavior.

## Operation evidence ledger

The parameter count includes the operation's scoped debug metadata.

| Operation | Parameters | Upstream source | SHA-256 |
| --- | ---: | --- | --- |
| `core.run` | 48 | `Sources/ContainerCommands/Container/ContainerRun.swift` | `4661c1cb186a41f0e3e04b6ef3b8765304d458cdf9d9216bbdf3bf4f26154377` |
| `core.build` | 25 | `Sources/ContainerCommands/BuildCommand.swift` | `ef5669d6a980c654ff441db6692b7ca3ef51d4cdb6009bb0b90655c63701bd73` |
| `containers.create` | 47 | `Sources/ContainerCommands/Container/ContainerCreate.swift` | `fcbc332b9fe86a30cd4c2b38ebaef5c52b2d670eb1143fa287afcfd7d84726d1` |
| `containers.start` | 4 | `Sources/ContainerCommands/Container/ContainerStart.swift` | `d212642c2b94ef0bf9740683fda1a56f04186434f3007c35944283333f9bc955` |
| `containers.stop` | 5 | `Sources/ContainerCommands/Container/ContainerStop.swift` | `bf18b60762db0f6285beed1728cb61b054acae2d7b3c113982765125523e35c3` |
| `containers.kill` | 4 | `Sources/ContainerCommands/Container/ContainerKill.swift` | `a0cd58a39676317d75d9a0f826b9b43c2d44c9c9945ae20aba34993cac55741b` |
| `containers.delete` | 4 | `Sources/ContainerCommands/Container/ContainerDelete.swift` | `63f9785fac9b9fe997bd746a9f5f8d7cb40fc8c3d2004a3c1e08d4757d9ee65b` |
| `containers.list` | 4 | `Sources/ContainerCommands/Container/ContainerList.swift` | `09da479718ac39e09333453717ee4c21ad9495e3356aaf1102ec8d1f211419ed` |
| `containers.exec` | 13 | `Sources/ContainerCommands/Container/ContainerExec.swift` | `376e2547dcb7efa89810fd6717b00634eca251f94cd607cca31a4537bd99a1dd` |
| `containers.export` | 3 | `Sources/ContainerCommands/Container/ContainerExport.swift` | `697953ca14bf4ede621aa2e64d61281ad1c502627f481acb62e68143c138afe0` |
| `containers.logs` | 5 | `Sources/ContainerCommands/Container/ContainerLogs.swift` | `4c93944714872b0348861f541642d08a06c29a7df4bb899c899d16376231c1b5` |
| `containers.inspect` | 2 | `Sources/ContainerCommands/Container/ContainerInspect.swift` | `80a9153547470e2b71c31bd4812eda3d3b05fa0da11532f0d38d3cfc136744a1` |
| `containers.stats` | 4 | `Sources/ContainerCommands/Container/ContainerStats.swift` | `65f1d537b8e1e2e2a948585cd4b71b607d99263174b2ebb3d0a2b5ade8e17a81` |
| `containers.copy` | 3 | `Sources/ContainerCommands/Container/ContainerCopy.swift` | `49322a3f5990f27378c6cd3507a83687a6a89a8093fc1c4784a241f14fd73f1a` |
| `containers.prune` | 1 | `Sources/ContainerCommands/Container/ContainerPrune.swift` | `c8b926390864a7c7682191ca82b889feb26064de133960b050f06b547f1a713e` |
| `images.list` | 4 | `Sources/ContainerCommands/Image/ImageList.swift` | `d846f0fe857a9677361493e43718876ca01dfb6ae6528ed978f60a1f715fd5c7` |
| `images.pull` | 8 | `Sources/ContainerCommands/Image/ImagePull.swift` | `ed9dd78bb8ef5c20083e77a7745bb0688b961e916dec3bf6fec4839b70f394be` |
| `images.push` | 7 | `Sources/ContainerCommands/Image/ImagePush.swift` | `611d446ea4888578d314b5f04586c6358ea484613f8ff6c7178dbf20d2832b9c` |
| `images.save` | 6 | `Sources/ContainerCommands/Image/ImageSave.swift` | `f266b739032e384713fef35ba96e900c43eb9872caf00f0a6fe302e218f883b7` |
| `images.load` | 3 | `Sources/ContainerCommands/Image/ImageLoad.swift` | `d079441b5378cf9067fdcab203032806edc06c3e66a5ec07cf863d5f9938b404` |
| `images.tag` | 3 | `Sources/ContainerCommands/Image/ImageTag.swift` | `36aebf2d62c57ee899033dc348e48bdaf205933786c93437befabb736cb41fb4` |
| `images.delete` | 4 | `Sources/ContainerCommands/Image/ImageDelete.swift` | `4f951d906cfcb2441eaf07cd66aad26c538dba71ee7c4c35fa3f2d93c671e2c9` |
| `images.prune` | 2 | `Sources/ContainerCommands/Image/ImagePrune.swift` | `f7ff1e15830a70564c139b16fdb8a12b3d19947e5acc67ae5e7a4773571bc68d` |
| `images.inspect` | 2 | `Sources/ContainerCommands/Image/ImageInspect.swift` | `087db2cf79bc635fe2b1ae9e97694ad462b74a4f9cdefc90bac1a4b30af15fe7` |
| `builder.start` | 7 | `Sources/ContainerCommands/Builder/BuilderStart.swift` | `4c5e117cc1619727c543386cfff4e26777c0cf50272740131b511bcf9e3d98f1` |
| `builder.status` | 3 | `Sources/ContainerCommands/Builder/BuilderStatus.swift` | `633f0102fd94973ce5627c3c0e48fb8c316aed31652230eca9347ddd51f68447` |
| `builder.stop` | 1 | `Sources/ContainerCommands/Builder/BuilderStop.swift` | `fef947f1732b6765869f4a45db73e3626ecab77434e9f66b97aea068c5dd79f8` |
| `builder.delete` | 2 | `Sources/ContainerCommands/Builder/BuilderDelete.swift` | `328dd2740be745ded24a6d002e101f1297fd24a64b91e4108c7be4ad74aaf9fb` |
| `networks.create` | 8 | `Sources/ContainerCommands/Network/NetworkCreate.swift` | `094bad8c4d37a39dbfbfcd1a52d8a200cea0833909da6ee52738f89c53a31c5c` |
| `networks.delete` | 3 | `Sources/ContainerCommands/Network/NetworkDelete.swift` | `01466f8c8c6871a706fe7977caeb6d4939e3dd3e3a90bc647f35e0ef9fa877e5` |
| `networks.prune` | 1 | `Sources/ContainerCommands/Network/NetworkPrune.swift` | `b91a0b40b9ed8687045c27adbd844b056d13ccaa489ba8334c4e0c4f263f0137` |
| `networks.list` | 3 | `Sources/ContainerCommands/Network/NetworkList.swift` | `bbce9eb7105a3ba03d19cf99525b8e61335dae725b7ec14d7cfb9e3981e3d7b0` |
| `networks.inspect` | 2 | `Sources/ContainerCommands/Network/NetworkInspect.swift` | `7e610448f5b7b05c5df24b18ac5f8e0901a6747f898ffa882a8197047ca3c7b6` |
| `volumes.create` | 5 | `Sources/ContainerCommands/Volume/VolumeCreate.swift` | `0434bf1a6beba7f2110986c5fb556eb82c5119e19a24ff1061210ea48ba151db` |
| `volumes.delete` | 3 | `Sources/ContainerCommands/Volume/VolumeDelete.swift` | `822ee0034747d2de2ffd7477ca75f8ec19b1e078219e8e071d995c65b4e329d4` |
| `volumes.prune` | 1 | `Sources/ContainerCommands/Volume/VolumePrune.swift` | `d3f51ed438aa194a65565b008d1b53c9daf3dedce5821a1cd888849cefd8bd1a` |
| `volumes.list` | 3 | `Sources/ContainerCommands/Volume/VolumeList.swift` | `e1d3625677a6e23fdafd242da834cbea0033b2f002bb69a35c4817de39e08fed` |
| `volumes.inspect` | 2 | `Sources/ContainerCommands/Volume/VolumeInspect.swift` | `1513fb9379bc7cc8c65b8c9b2111413b29df7e30365dd69b35f660dfab80d0dc` |
| `registries.login` | 6 | `Sources/ContainerCommands/Registry/RegistryLogin.swift` | `15fbb07969b4392dc895dc4fc6a19088865bd5aaefa22eb8dfdf338f8ced395c` |
| `registries.logout` | 2 | `Sources/ContainerCommands/Registry/RegistryLogout.swift` | `ae94e4aefe7c40a1e93835102f1edc926cc41cf016569155e501b411dfc89909` |
| `registries.list` | 3 | `Sources/ContainerCommands/Registry/RegistryList.swift` | `e7a4ec3885f0574aee10facf1780941c073d0fb651f40126800266c70a286384` |
| `machines.create` | 16 | `Sources/ContainerCommands/Machine/MachineCreate.swift` | `c23e6207d75284acf5dd2fd2a6e69eee4f28c894e8b5f812ec6a770f507f5b03` |
| `machines.run` | 15 | `Sources/ContainerCommands/Machine/MachineRun.swift` | `5d95c10b54a9b3eb1110942b90792f68f65edfc3ae0a04746d8b6baeedade97a` |
| `machines.list` | 3 | `Sources/ContainerCommands/Machine/MachineList.swift` | `9566cebf75aa955b9e91a4b9591d9b76701bc1f2b0f48971b44959b4defb2ae8` |
| `machines.inspect` | 2 | `Sources/ContainerCommands/Machine/MachineInspect.swift` | `77bc3c3b44db9dd96b7e5d9264043e8f24473e7d20f9376c9c0af8339f4c3fd9` |
| `machines.set` | 3 | `Sources/ContainerCommands/Machine/MachineSet.swift` | `25fda22ad38141d9f6a7ec0e3517be4f9154a0c951fe2cf56bb4ec3b5a94e49f` |
| `machines.set-default` | 2 | `Sources/ContainerCommands/Machine/MachineSetDefault.swift` | `fa12de9d7f1509a944e891c2ab398dc68a95f57a5b903cab5fc9c446e791f13d` |
| `machines.logs` | 5 | `Sources/ContainerCommands/Machine/MachineLogs.swift` | `b30da7d49cfaba875cdd8e2c0afbd727ccc4dd6cc3cd9fb13173fdfbe087ae47` |
| `machines.stop` | 3 | `Sources/ContainerCommands/Machine/MachineStop.swift` | `6b0c145fffdddb2972863dd3f6fac5a3e43a995e2f8ee039bec1877c4b6acb58` |
| `machines.delete` | 3 | `Sources/ContainerCommands/Machine/MachineDelete.swift` | `49a77ccf34973d4893cacbef258c225f801cef0453e4a36dd08ee5d7eb267f8b` |
| `system.start` | 6 | `Sources/ContainerCommands/System/SystemStart.swift` | `99d905c955f294d7ec0fdd461dcdc3d074212c7975ae58e57c92840180f2df55` |
| `system.stop` | 2 | `Sources/ContainerCommands/System/SystemStop.swift` | `0ea5199af6862c85a02cff7b47aa0b3e26d3b21093d3ff172142b38afedc28f8` |
| `system.status` | 3 | `Sources/ContainerCommands/System/SystemStatus.swift` | `aafea640e6eed05e49af3568a40328f022a1683d38b29dfae0cac42a1525f06c` |
| `system.version` | 2 | `Sources/ContainerCommands/System/SystemVersion.swift` | `15294fb9b1d6a2f2c393a1f832481da9c1ab9e1f8914ab9946e94a8d9915ac36` |
| `system.logs` | 3 | `Sources/ContainerCommands/System/SystemLogs.swift` | `7ce9b42df9048369e88bffe8e054c58b35882a5f7f01ecc9b89c128fc37f9966` |
| `system.disk-usage` | 2 | `Sources/ContainerCommands/System/SystemDF.swift` | `f44276bb35c771f4bd5043d48cdad5008f1c7a08894ff6bf8a5fa745e5296254` |
| `dns.create` | 3 | `Sources/ContainerCommands/System/DNS/DNSCreate.swift` | `3777506ab15ad834cc6d096f131401bcf7944820aeb4495d0f80e8a68e443620` |
| `dns.delete` | 2 | `Sources/ContainerCommands/System/DNS/DNSDelete.swift` | `85c63ac3a55a263d8593c0f9afbec069de6265de8b6ed1613c5c741e894506bd` |
| `dns.list` | 3 | `Sources/ContainerCommands/System/DNS/DNSList.swift` | `301f47825a14e7a7433cb170fea7805303ae34a6cbfa8d34d57f8cd3a9fdfeda` |
| `kernel.set` | 6 | `Sources/ContainerCommands/System/Kernel/KernelSet.swift` | `2506f498495cfe6dc51c46964e6e696d70bffe2d1b889ed1fc1584340fe21d3b` |
| `configuration.manage` | 2 | `Sources/ContainerCommands/System/Property/PropertyList.swift` | `d04ab933d285048857b205508915a70c6105b39b93eca58659c32da5f8396c9f` |
