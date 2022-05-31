// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.12;

contract AddressRegistry {

    /**************************/
    /*** External Contracts ***/
    /**************************/

    address constant DAI  = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant MPL  = 0x33349B282065b0284d756F0577FB39c158F935e6;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

    address constant BPOOL_FACTORY      = 0x9424B1412450D0f8Fc2255FAf6046b98213B76Bd;
    address constant USDC_BALANCER_POOL = 0xc1b10e536CD611aCFf7a7c32A9E29cE6A02Ef6ef;

    /***********************/
    /*** Maple Contracts ***/
    /***********************/

    address constant GOVERNOR       = 0xd6d4Bcde6c816F17889f1Dd3000aF0261B03a196;
    address constant MAPLE_GLOBALS  = 0xC234c62c8C09687DFf0d9047e40042cd166F3600;
    address constant POOL_FACTORY   = 0x2Cd79F7f8b38B9c0D80EA6B230441841A31537eC;
    address constant LOAN_FACTORY   = 0x908cC851Bc757248514E060aD8Bd0a03908308ee;
    address constant CL_FACTORY     = 0xEE3e59D381968f4F9C92460D9d5Cfcf5d3A67987;
    address constant DL_FACTORY     = 0x2a7705594899Db6c3924A872676E54f041d1f9D8;
    address constant FL_FACTORY     = 0x0eB96A53EC793a244876b018073f33B23000F25b;
    address constant SL_FACTORY     = 0x53a597A4730Eb02095dD798B203Dcc306348B8d6;
    address constant LL_FACTORY     = 0x966528BB1C44f96b3AA8Fbf411ee896116b068C9;
    address constant REPAYMENT_CALC = 0x7d622bB6Ed13a599ec96366Fa95f2452c64ce602;
    address constant LATEFEE_CALC   = 0x8dC5aa328142aa8a008c25F66a77eaA8E4B46f3c;
    address constant PREMIUM_CALC   = 0xe88Ab4Cf1Ec06840d16feD69c964aD9DAFf5c6c2;
    address constant USD_ORACLE     = 0x5DC5E14be1280E747cD036c089C96744EBF064E7;

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
