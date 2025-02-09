const {deployProxy} = require('@openzeppelin/truffle-upgrades');

const SmallABCToken = artifacts.require("SmallABCToken");
const gnosisSafe = process.env.GNOSIS_SAFE;

module.exports = async function (deployer, network, accounts) {
    // Don't setup Gnosis Safe as owner our develop network
    const instance = network === 'develop'
        ? await deployProxy(SmallABCToken, [accounts[1]], {deployer})
        : await deployProxy(SmallABCToken, [gnosisSafe], {deployer});

    console.log('Contract Proxy address: ', instance.address);
};