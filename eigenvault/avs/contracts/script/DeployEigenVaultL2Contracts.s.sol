// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {IBN254CertificateVerifier} from
    "@eigenlayer-contracts/src/contracts/interfaces/IBN254CertificateVerifier.sol";
import {IECDSACertificateVerifier} from "@eigenlayer-contracts/src/contracts/interfaces/IECDSACertificateVerifier.sol";
import {ITaskMailbox} from "@eigenlayer-contracts/src/contracts/interfaces/ITaskMailbox.sol";

import {EigenVaultAVSTaskHook} from "@project/l2-contracts/EigenVaultAVSTaskHook.sol";

contract DeployEigenVaultL2Contracts is Script {
    using stdJson for string;

    struct Context {
        address avs;
        uint256 avsPrivateKey;
        uint256 deployerPrivateKey;
        IBN254CertificateVerifier certificateVerifier;
        IECDSACertificateVerifier ecdsaCertificateVerifier;
        ITaskMailbox taskMailbox;
        EigenVaultAVSTaskHook taskHook;
        address eigenVaultHook; // Main EigenVault Hook contract address
    }

    struct Output {
        string name;
        address contractAddress;
    }

    function run(string memory environment, string memory _context) public {
        // Read the context
        Context memory context = _readContext(environment, _context);

        vm.startBroadcast(context.deployerPrivateKey);
        console.log("Deployer address:", vm.addr(context.deployerPrivateKey));

        // Deploy custom EigenVault L2 contracts
        console.log("Deploying EigenVault L2 contracts...");
        
        // Deploy additional EigenVault-specific L2 contracts if needed
        // For example: EigenVaultL2Manager, OrderProcessor, PrivacyManager, etc.
        
        console.log("EigenVault L2 contracts deployment completed");

        vm.stopBroadcast();

        vm.startBroadcast(context.avsPrivateKey);
        console.log("AVS address:", context.avs);

        // Configure the EigenVault AVS Task Hook
        console.log("Configuring EigenVault AVS Task Hook...");
        
        // Set the main EigenVault Hook contract address
        if (context.eigenVaultHook != address(0)) {
            context.taskHook.setEigenVaultHook(context.eigenVaultHook);
            console.log("EigenVault Hook address set to:", context.eigenVaultHook);
        }
        
        // Additional AVS-specific configuration
        console.log("AVS L2 configuration completed");

        vm.stopBroadcast();

        // Write output to JSON file
        Output[] memory outputs = new Output[](0);
        // Note: Add any deployed contracts to the outputs array
        // Example:
        // outputs[0] = Output({name: "EigenVaultL2Manager", contractAddress: address(eigenVaultL2Manager)});
        _writeOutputToJson(environment, outputs);
    }

    function _readContext(
        string memory environment,
        string memory _context
    ) internal view returns (Context memory) {
        // Parse the context
        Context memory context;
        context.avs = stdJson.readAddress(_context, ".context.avs.address");
        context.avsPrivateKey = uint256(stdJson.readBytes32(_context, ".context.avs.avs_private_key"));
        context.deployerPrivateKey = uint256(stdJson.readBytes32(_context, ".context.deployer_private_key"));
        context.certificateVerifier = IBN254CertificateVerifier(stdJson.readAddress(_context, ".context.eigenlayer.l2.bn254_certificate_verifier"));
        context.ecdsaCertificateVerifier = IECDSACertificateVerifier(stdJson.readAddress(_context, ".context.eigenlayer.l2.ecdsa_certificate_verifier"));
        context.taskMailbox = ITaskMailbox(_readHourglassConfigAddress(environment, "taskMailbox"));
        context.taskHook = EigenVaultAVSTaskHook(_readAVSL2ConfigAddress(environment, "avsTaskHook"));
        
        // Read EigenVault Hook address from context (this would be deployed separately)
        try stdJson.readAddress(_context, ".context.eigenvault.hook_address") returns (address hookAddr) {
            context.eigenVaultHook = hookAddr;
        } catch {
            context.eigenVaultHook = address(0);
        }

        return context;
    }

    function _readHourglassConfigAddress(
        string memory environment,
        string memory key
    ) internal view returns (address) {
        // Load the Hourglass config file
        string memory hourglassConfigFile =
                            string.concat("script/", environment, "/output/deploy_hourglass_core_output.json");
        string memory hourglassConfig = vm.readFile(hourglassConfigFile);

        // Parse and return the address
        return stdJson.readAddress(hourglassConfig, string.concat(".addresses.", key));
    }

    function _readAVSL2ConfigAddress(string memory environment, string memory key) internal view returns (address) {
        // Load the AVS L2 config file
        string memory avsL2ConfigFile = string.concat("script/", environment, "/output/deploy_avs_l2_output.json");
        string memory avsL2Config = vm.readFile(avsL2ConfigFile);

        // Parse and return the address
        return stdJson.readAddress(avsL2Config, string.concat(".addresses.", key));
    }

    function _writeOutputToJson(
        string memory environment,
        Output[] memory outputs
    ) internal {
        uint256 length = outputs.length;

        if (length > 0) {
            // Add the addresses object
            string memory addresses = "addresses";

            for (uint256 i = 0; i < outputs.length - 1; i++) {
                vm.serializeAddress(addresses, outputs[i].name, outputs[i].contractAddress);
            }
            addresses = vm.serializeAddress(addresses, outputs[length - 1].name, outputs[length - 1].contractAddress);

            // Add the chainInfo object
            string memory chainInfo = "chainInfo";
            chainInfo = vm.serializeUint(chainInfo, "chainId", block.chainid);

            // Finalize the JSON
            string memory finalJson = "final";
            vm.serializeString(finalJson, "addresses", addresses);
            finalJson = vm.serializeString(finalJson, "chainInfo", chainInfo);

            // Write to output file
            string memory outputFile = string.concat("script/", environment, "/output/deploy_eigenvault_l2_output.json");
            vm.writeJson(finalJson, outputFile);
        } else {
            // Write empty output file
            string memory emptyJson = "{}";
            string memory outputFile = string.concat("script/", environment, "/output/deploy_eigenvault_l2_output.json");
            vm.writeFile(outputFile, emptyJson);
        }
    }
}