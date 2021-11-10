const { NonceManager } = require("@ethersproject/experimental");

const delay = ms => new Promise(res => setTimeout(res, ms));
const etherscanChains = ["poly", "bsc", "poly_mumbai", "ftm", "arbitrum"];
const sourcifyChains = ["xdai", "celo", "avax", "avax_fuji", "arbitrum"];

const main = async function (hre) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();
    const managedDeployer = new NonceManager(deployer);
    const signer = await hre.ethers.getSigner(deployer);
    
    // We get the contract to deploy
    const zapHandlerV1 = await deploy("ZapHandlerV1", { from: managedDeployer.signer, log: true, args: [signer.address] , 
        deterministicDeployment: "0x9c22ff5f21f0b81b113e63f7db6da94fedef11b2119b4088b89664fb9a3cb658" });
    console.log("ZapHandlerV1 deployed to:", zapHandlerV1.address);

    const zap = await deploy("Zap", { from: managedDeployer.signer, log: true, args: [signer.address], 
        deterministicDeployment: "0x9c22ff5f21f0b81b113e63f7db6da94fedef11b2119b4088b89664fb9a3cb658" });
    const ZapContractFactory = await ethers.getContractFactory("Zap");
    const zapContract = await ZapContractFactory.attach(zap.address);
    if((await zapContract.implementation()) !== zapHandlerV1.address){
        await zapContract.connect(signer).setImplementation(zapHandlerV1.address);
        console.log("set zap implementation to zapHandlerV1");
    }

    const chain = hre.network.name;
    try {
        await verify(hre, chain, zap.address, signer.address);
    } catch (error) {
        console.log(error);
    }

    try {
        await verify(hre, chain, zapHandlerV1.address, signer.address);
    } catch{}
}

async function verify(hre, chain, contract, owner) {
    const isEtherscanAPI = etherscanChains.includes(chain);
    const isSourcify = sourcifyChains.includes(chain);
    if(!isEtherscanAPI && !isSourcify)
        return;

    console.log('verifying...');
    await delay(5000);
    if (isEtherscanAPI) {
        await hre.run("verify:verify", {
            address: contract,
            network: chain,
            constructorArguments: [owner]
        });
    } else if (isSourcify) {
        try {
            await hre.run("sourcify", {
                address: contract,
                network: chain,
                constructorArguments: [owner]
            });
        } catch (error) {
            console.log("verification failed: sourcify not supported?");
        }
    }
}

module.exports = main;