const {DataServiceWrapper} = require("@redstone-finance/evm-connector");

async function getPayload() {
  const feed = process.argv[2];
  const wrapper = new DataServiceWrapper({
    dataServiceId: "redstone-primary-prod",
    dataFeeds: [feed],
    uniqueSignersCount: 3
  });
  const redstonePayload = await wrapper.getBytesDataForAppending();
  console.log(redstonePayload);
}

getPayload();