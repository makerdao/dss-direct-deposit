pragma solidity ^0.8.14;

contract AddressRegistry {

    /**************************/
    /*** External Contracts ***/
    /**************************/

    address constant DAI  = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant MPL  = 0x33349B282065b0284d756F0577FB39c158F935e6;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

    /***********************/
    /*** TrueFi Contracts ***/
    /***********************/

    address constant MANAGED_PORTFOLIO_FACTORY_PROXY      = 0x17b7b75FD4288197cFd99D20e13B0dD9da1FF3E7;
    address constant GLOBAL_WHITELIST_LENDER_VERIFIER     = 0xAe48bea8F3FC1696DC8ec75183705CeE1D071B05;
    address constant SIGNATURE_ONLY_LENDER_VERIFIER       = 0xc9406Eb56804BCC850b88B5493Ad35d52FDdae79;

    /***********************/
    /*** Maker Contracts ***/
    /***********************/

    address constant CHAINLOG    = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;
    address constant DAI_JOIN    = 0x9759A6Ac90977b93B58547b4A71c78317f391A28;
    address constant END         = 0xBB856d1742fD182a90239D7AE85706C2FE4e5922;
    address constant PAUSE_PROXY = 0xBE8E3e3618f7474F8cB1d074A26afFef007E98FB;
    address constant SPOT        = 0x65C79fcB50Ca1594B025960e539eD7A9a6D434A3;
    address constant VAT         = 0x35D1b3F3D7966A1DFe207aa4514C12a259A0492B;
    address constant VOW         = 0xA950524441892A31ebddF91d3cEEFa04Bf454466;

}
