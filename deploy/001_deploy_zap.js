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
    const zapHandlerV1 = await deploy("ZapHandlerV1", { from: managedDeployer.signer, log: true, args: [] });
    console.log("ZapHandlerV1 deployed to:", zapHandlerV1.address);

    const zap = await deploy("Zap", { from: managedDeployer.signer, log: true, args: [] });
    const ZapContractFactory = await ethers.getContractFactory("Zap");
    const zapContract = await ZapContractFactory.attach(zap.address);
    if((await zapContract.implementation()) !== zapHandlerV1.address){
        await zapContract.connect(signer).setImplementation(zapHandlerV1.address);
        console.log("set zap implementation to zapHandlerV1");
    }

    const chain = hre.network.name;
    try {
        await verify(hre, chain, zap.address);
    } catch {}
    try {
        await verify(hre, chain, zapHandlerV1.address);
    } catch{}
}

async function verify(hre, chain, contract) {
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
            constructorArguments: []
        });
    } else if (isSourcify) {
        try {
            await hre.run("sourcify", {
                address: contract,
                network: chain,
                constructorArguments: []
            });
        } catch (error) {
            console.log("verification failed: sourcify not supported?");
        }
    }
}

module.exports = main;