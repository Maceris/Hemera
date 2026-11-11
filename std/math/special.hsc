package math

import intrinsics from "base"

/*
 * The error function, its complement and inverse, and the gamma function and its logarithm, in f64 (fdlibm's s_erf.c
 * and e_lgamma_r.c, musl's tgamma.c). The constants' hex is their bits, high word then low.
 */

/** erf(1)'s top 24 bits. */
ERF_X : f64 : 8.45062911510467529297e-01 // 0x3feb0ac1_60000000
/** 2/√π - 1. */
ERF_EFX : f64 : 1.28379167095512586316e-01 // 0x3fc06eba_8214db69
/** 8 × ERF_EFX. */
ERF_EFX8 : f64 : 1.02703333676410069053 // 0x3ff06eba_8214db69
/* erf on [0, 0.84375]: x + x × P(x²) / Q(x²) */
ERF_PP0 : f64 : 1.28379167095512558561e-01 // 0x3fc06eba_8214db68
ERF_PP1 : f64 : -3.25042107247001499370e-01 // 0xbfd4cd7d_691cb913
ERF_PP2 : f64 : -2.84817495755985104766e-02 // 0xbf9d2a51_dbd7194f
ERF_PP3 : f64 : -5.77027029648944159157e-03 // 0xbf77a291_236668e4
ERF_PP4 : f64 : -2.37630166566501626084e-05 // 0xbef8ead6_120016ac
ERF_QQ1 : f64 : 3.97917223959155352819e-01 // 0x3fd97779_cddadc09
ERF_QQ2 : f64 : 6.50222499887672944485e-02 // 0x3fb0a54c_5536ceba
ERF_QQ3 : f64 : 5.08130628187576562776e-03 // 0x3f74d022_c4d36b0f
ERF_QQ4 : f64 : 1.32494738004321644526e-04 // 0x3f215dc9_221c1a10
ERF_QQ5 : f64 : -3.96022827877536812320e-06 // 0xbed09c43_42a26120
/* erf on [0.84375, 1.25], about 1: erx + P(s) / Q(s), s = |x| - 1 */
ERF_PA0 : f64 : -2.36211856075265944077e-03 // 0xbf6359b8_bef77538
ERF_PA1 : f64 : 4.14856118683748331666e-01 // 0x3fda8d00_ad92b34d
ERF_PA2 : f64 : -3.72207876035701323847e-01 // 0xbfd7d240_fbb8c3f1
ERF_PA3 : f64 : 3.18346619901161753674e-01 // 0x3fd45fca_805120e4
ERF_PA4 : f64 : -1.10894694282396677476e-01 // 0xbfbc6398_3d3e28ec
ERF_PA5 : f64 : 3.54783043256182359371e-02 // 0x3fa22a36_599795eb
ERF_PA6 : f64 : -2.16637559486879084300e-03 // 0xbf61bf38_0a96073f
ERF_QA1 : f64 : 1.06420880400844228286e-01 // 0x3fbb3e66_18eee323
ERF_QA2 : f64 : 5.40397917702171048937e-01 // 0x3fe14af0_92eb6f33
ERF_QA3 : f64 : 7.18286544141962662868e-02 // 0x3fb2635c_d99fe9a7
ERF_QA4 : f64 : 1.26171219808761642112e-01 // 0x3fc02660_e763351f
ERF_QA5 : f64 : 1.36370839120290507362e-02 // 0x3f8bedc2_6b51dd1c
ERF_QA6 : f64 : 1.19844998467991074170e-02 // 0x3f888b54_5735151d
/* erfc on [1.25, 1/0.35]: e^(-x² - 0.5625 + R(1/x²) / S(1/x²)) / x */
ERF_RA0 : f64 : -9.86494403484714822705e-03 // 0xbf843412_600d6435
ERF_RA1 : f64 : -6.93858572707181764372e-01 // 0xbfe63416_e4ba7360
ERF_RA2 : f64 : -1.05586262253232909814e01 // 0xc0251e04_41b0e726
ERF_RA3 : f64 : -6.23753324503260060396e01 // 0xc04f300a_e4cba38d
ERF_RA4 : f64 : -1.62396669462573470355e02 // 0xc0644cb1_84282266
ERF_RA5 : f64 : -1.84605092906711035994e02 // 0xc067135c_ebccabb2
ERF_RA6 : f64 : -8.12874355063065934246e01 // 0xc0545265_57e4d2f2
ERF_RA7 : f64 : -9.81432934416914548592 // 0xc023a0ef_c69ac25c
ERF_SA1 : f64 : 1.96512716674392571292e01 // 0x4033a6b9_bd707687
ERF_SA2 : f64 : 1.37657754143519042600e02 // 0x4061350c_526ae721
ERF_SA3 : f64 : 4.34565877475229228821e02 // 0x407b290d_d58a1a71
ERF_SA4 : f64 : 6.45387271733267880336e02 // 0x40842b19_21ec2868
ERF_SA5 : f64 : 4.29008140027567833386e02 // 0x407ad021_57700314
ERF_SA6 : f64 : 1.08635005541779435134e02 // 0x405b28a3_ee48ae2c
ERF_SA7 : f64 : 6.57024977031928170135 // 0x401a47ef_8e484a93
ERF_SA8 : f64 : -6.04244152148580987438e-02 // 0xbfaeeff2_ee749a62
/* erfc on [1/0.35, 28] */
ERF_RB0 : f64 : -9.86494292470009928597e-03 // 0xbf843412_39e86f4a
ERF_RB1 : f64 : -7.99283237680523006574e-01 // 0xbfe993ba_70c285de
ERF_RB2 : f64 : -1.77579549177547519889e01 // 0xc031c209_555f995a
ERF_RB3 : f64 : -1.60636384855821916062e02 // 0xc064145d_43c5ed98
ERF_RB4 : f64 : -6.37566443368389627722e02 // 0xc083ec88_1375f228
ERF_RB5 : f64 : -1.02509513161107724954e03 // 0xc0900461_6a2e5992
ERF_RB6 : f64 : -4.83519191608651397019e02 // 0xc07e384e_9bdc383f
ERF_SB1 : f64 : 3.03380607434824582924e01 // 0x403e568b_261d5190
ERF_SB2 : f64 : 3.25792512996573918826e02 // 0x40745cae_221b9f0a
ERF_SB3 : f64 : 1.53672958608443695994e03 // 0x409802eb_189d5118
ERF_SB4 : f64 : 3.19985821950859553908e03 // 0x40a8ffb7_688c246a
ERF_SB5 : f64 : 2.55305040643316442583e03 // 0x40a3f219_cedf3be6
ERF_SB6 : f64 : 4.74528541206955367215e02 // 0x407da874_e79fe763
ERF_SB7 : f64 : -2.24409524465858183362e01 // 0xc03670e2_42712d62

/**
 * erf's and erfc's e^(-x² - 0.5625 + R/S) / x on [1.25, 28], for x positive: erfc x.
 *
 * @param x The number, from 1.25 to 28.
 * @param ix x's high word.
 * @return erfc x.
 */
//SPEC: fdlibm s_erf.c
erfc_tail_64 :: fn(x: f64, ix: i32) -> f64 {
    s :: 1 / (x * x)
    r := 0.0
    q := 0.0
    if ix < 0x4006_db6e {
        r = ERF_RA0 + s * (ERF_RA1 + s * (ERF_RA2 + s * (ERF_RA3 + s * (ERF_RA4 + s * (ERF_RA5 + s * (ERF_RA6
            + s * ERF_RA7))))))
        q = 1 + s * (ERF_SA1 + s * (ERF_SA2 + s * (ERF_SA3 + s * (ERF_SA4 + s * (ERF_SA5 + s * (ERF_SA6 + s * (ERF_SA7
            + s * ERF_SA8)))))))
    }
    else {
        r = ERF_RB0 + s * (ERF_RB1 + s * (ERF_RB2 + s * (ERF_RB3 + s * (ERF_RB4 + s * (ERF_RB5 + s * ERF_RB6)))))
        q = 1 + s * (ERF_SB1 + s * (ERF_SB2 + s * (ERF_SB3 + s * (ERF_SB4 + s * (ERF_SB5 + s * (ERF_SB6
            + s * ERF_SB7))))))
    }
    // x² split, so -z² is exact and e^(-x²) loses nothing
    z :: with_low_word(x, 0)
    return exp_64(-z * z - 0.5625) * exp_64((z - x) * (z + x) + r / q) / x
}

/**
 * erf about 1: erf|x| - erx, for |x| from 0.84375 to 1.25.
 *
 * @param s |x| - 1.
 * @return P(s) / Q(s).
 */
erf_near_one_64 :: fn(s: f64) -> f64 {
    p :: ERF_PA0 + s * (ERF_PA1 + s * (ERF_PA2 + s * (ERF_PA3 + s * (ERF_PA4 + s * (ERF_PA5 + s * ERF_PA6)))))
    q :: 1 + s * (ERF_QA1 + s * (ERF_QA2 + s * (ERF_QA3 + s * (ERF_QA4 + s * (ERF_QA5 + s * ERF_QA6)))))
    return p / q
}

/**
 * erf's P(z) / Q(z) near 0.
 *
 * @param z x².
 * @return P(z) / Q(z).
 */
erf_near_zero_64 :: fn(z: f64) -> f64 {
    r :: ERF_PP0 + z * (ERF_PP1 + z * (ERF_PP2 + z * (ERF_PP3 + z * ERF_PP4)))
    s :: 1 + z * (ERF_QQ1 + z * (ERF_QQ2 + z * (ERF_QQ3 + z * (ERF_QQ4 + z * ERF_QQ5))))
    return r / s
}

/**
 * The error function, erf x = 2/√π ∫₀ˣ e^(-t²) dt, in f64.
 *
 * @param x The number.
 * @return erf x, within 1 ulp; ±1 for ±infinity, x for ±0, NaN for NaN.
 */
//SPEC: fdlibm s_erf.c
erf_64 :: fn(x: f64) -> f64 {
    hx :: high_word(x)
    ix :: hx & 0x7fff_ffff
    if ix >= 0x7ff0_0000 {
        if x != x {
            return x + x
        }
        return if hx < 0 { -1.0 } else { 1.0 }
    }
    if ix < 0x3feb_0000 {
        // Under 2^-28: x + x × (2/√π - 1)
        if ix < 0x3e30_0000 {
            if ix < 0x0080_0000 {
                return (8 * x + ERF_EFX8 * x) / 8
            }
            return x + ERF_EFX * x
        }
        return x + x * erf_near_zero_64(x * x)
    }
    if ix < 0x3ff4_0000 {
        p :: erf_near_one_64(abs(x) - 1)
        return if hx >= 0 { ERF_X + p } else { -ERF_X - p }
    }
    // From 6, erf x rounds to ±1
    if ix >= 0x4018_0000 {
        return if hx >= 0 { 1.0 } else { -1.0 }
    }
    r :: erfc_tail_64(abs(x), ix)
    return if hx >= 0 { 1 - r } else { r - 1 }
}

/**
 * The complementary error function, erfc x = 1 - erf x, in f64, accurate where erf x is near 1.
 *
 * @param x The number.
 * @return erfc x, within 1 ulp, and 2 far in its tail; 0 for infinity, 2 for -infinity, NaN for NaN.
 */
//SPEC: fdlibm s_erf.c
erfc_64 :: fn(x: f64) -> f64 {
    hx :: high_word(x)
    ix :: hx & 0x7fff_ffff
    if ix >= 0x7ff0_0000 {
        if x != x {
            return x + x
        }
        return if hx < 0 { 2.0 } else { 0.0 }
    }
    if ix < 0x3feb_0000 {
        // Under 2^-56
        if ix < 0x3c70_0000 {
            return 1 - x
        }
        y :: erf_near_zero_64(x * x)
        if hx < 0x3fd0_0000 {
            // Under a quarter
            return 1 - (x + x * y)
        }
        r := x * y
        r += x - 0.5
        return 0.5 - r
    }
    if ix < 0x3ff4_0000 {
        p :: erf_near_one_64(abs(x) - 1)
        if hx >= 0 {
            return (1 - ERF_X) - p
        }
        return 1 + (ERF_X + p)
    }
    if ix < 0x403c_0000 {
        // Below -6, erfc x rounds to 2
        if hx < 0 && ix >= 0x4018_0000 {
            return 2
        }
        r :: erfc_tail_64(abs(x), if ix < 0x4006_db6d { ix } else { 0x4006_db6e })
        return if hx > 0 { r } else { 2 - r }
    }
    return if hx > 0 { 0.0 } else { 2.0 }
}

/**
 * The inverse error function in f64: the x whose erf is y.
 *
 * A first guess from Giles' approximation, then Halley's method on erf and erfc, which roughly triples the correct
 * bits each step: two steps from the guess's 6 digits or so reach f64's precision.
 *
 * @param y The value of erf, from -1 to 1.
 * @return x with erf x = y, within 2 ulp; ±infinity at ±1, NaN beyond ±1 and for NaN, y for ±0.
 */
//SPEC: M. Giles, "Approximating the erfinv function", GPU Computing Gems Jade Edition (2011), single precision
erf_inverse_64 :: fn(y: f64) -> f64 {
    if y != y || y < -1 || y > 1 {
        return nan_64()
    }
    if y == 1 {
        return infinity_64()
    }
    if y == -1 {
        return -infinity_64()
    }
    if y == 0 {
        return y
    }
    // Giles' guess, in w = -ln(1 - y²)
    w := -log_one_plus_64(-y * y)
    p := 0.0
    if w < 6.25 {
        w -= 3.125
        p = -3.6444120640178196996e-21
        p = -1.685059138182016589e-19 + p * w
        p = 1.2858480715256400167e-18 + p * w
        p = 1.115787767802518096e-17 + p * w
        p = -1.333171662854620906e-16 + p * w
        p = 2.0972767875968561637e-17 + p * w
        p = 6.6376381343583238325e-15 + p * w
        p = -4.0545662729752068639e-14 + p * w
        p = -8.1519341976054721522e-14 + p * w
        p = 2.6335093153082322977e-12 + p * w
        p = -1.2975133253453532498e-11 + p * w
        p = -5.4154120542946279317e-11 + p * w
        p = 1.051212273321532285e-09 + p * w
        p = -4.1126339803469836976e-09 + p * w
        p = -2.9070369957882005086e-08 + p * w
        p = 4.2347877827932403518e-07 + p * w
        p = -1.3654692000834678645e-06 + p * w
        p = -1.3882523362786468719e-05 + p * w
        p = 0.0001867342080340571352 + p * w
        p = -0.00074070253416626697512 + p * w
        p = -0.0060336708714301490533 + p * w
        p = 0.24015818242558961693 + p * w
        p = 1.6536545626831027356 + p * w
    }
    else if w < 16.0 {
        w = intrinsics.square_root(w) - 3.25
        p = 2.2137376921775787049e-09
        p = 9.0756561938885390979e-08 + p * w
        p = -2.7517406297064545428e-07 + p * w
        p = 1.8239629214389227755e-08 + p * w
        p = 1.5027403968909827627e-06 + p * w
        p = -4.013867526981545969e-06 + p * w
        p = 2.9234449089955446044e-06 + p * w
        p = 1.2475304481671778723e-05 + p * w
        p = -4.7318229009055733981e-05 + p * w
        p = 6.8284851459573175448e-05 + p * w
        p = 2.4031110387097893999e-05 + p * w
        p = -0.0003550375203628474796 + p * w
        p = 0.00095328937973738049703 + p * w
        p = -0.0016882755560235047313 + p * w
        p = 0.0024914420961078508066 + p * w
        p = -0.0037512085075692412107 + p * w
        p = 0.005370914553590063617 + p * w
        p = 1.0052589676941592334 + p * w
        p = 3.0838856104922207635 + p * w
    }
    else {
        w = intrinsics.square_root(w) - 5.0
        p = -2.7109920616438573243e-11
        p = -2.5556418169965252055e-10 + p * w
        p = 1.5076572693500548083e-09 + p * w
        p = -3.7894654401267369937e-09 + p * w
        p = 7.6157012080783393804e-09 + p * w
        p = -1.4960026627149240478e-08 + p * w
        p = 2.9147953450901080826e-08 + p * w
        p = -6.7711997758452339498e-08 + p * w
        p = 2.2900482228026654717e-07 + p * w
        p = -9.9298272942317002539e-07 + p * w
        p = 4.5260625972231537039e-06 + p * w
        p = -1.9681778105531670567e-05 + p * w
        p = 7.5995277030017761139e-05 + p * w
        p = -0.00021503011930044477347 + p * w
        p = -0.00013871931833623122026 + p * w
        p = 1.0103004648645343977 + p * w
        p = 4.8499064014085844221 + p * w
    }
    x := p * y
    // Halley's method: f = erf x - y, f' = 2/√π e^(-x²), f'' = -2x f'; near ±1, from erfc, which keeps what erf loses
    step : i32 = 0
    loop {
        error :: if abs(y) < 0.5 { erf_64(x) - y } else if y > 0 { (1 - y) - erfc_64(x) } else { erfc_64(-x) - (1 + y) }
        slope :: TWO_OVER_SQRT_PI * exp_64(-x * x)
        if slope == 0 {
            break
        }
        newton :: error / slope
        x -= newton / (1 + x * newton)
        step += 1
    }
    while step < 2
    return x
}

/** 2/√π. */
TWO_OVER_SQRT_PI : f64 : 1.12837916709551257390

/* log Γ's constants: about the minimum tc, and in the ranges e_lgamma_r.c splits [0, 8) into */
LGAMMA_A0 : f64 : 7.72156649015328655494e-02 // 0x3fb3c467_e37db0c8
LGAMMA_A1 : f64 : 3.22467033424113591611e-01 // 0x3fd4a34c_c4a60fad
LGAMMA_A2 : f64 : 6.73523010531292681824e-02 // 0x3fb13e00_1a5562a7
LGAMMA_A3 : f64 : 2.05808084325167332806e-02 // 0x3f951322_ac92547b
LGAMMA_A4 : f64 : 7.38555086081402883957e-03 // 0x3f7e404f_b68fefe8
LGAMMA_A5 : f64 : 2.89051383673415629091e-03 // 0x3f67add8_ccb7926b
LGAMMA_A6 : f64 : 1.19270763183362067845e-03 // 0x3f538a94_116f3f5d
LGAMMA_A7 : f64 : 5.10069792153511336608e-04 // 0x3f40b6c6_89b99c00
LGAMMA_A8 : f64 : 2.20862790713908385557e-04 // 0x3f2cf2ec_ed10e54d
LGAMMA_A9 : f64 : 1.08011567247583939954e-04 // 0x3f1c5088_987dfb07
LGAMMA_A10 : f64 : 2.52144565451257326939e-05 // 0x3efa7074_428cfa52
LGAMMA_A11 : f64 : 4.48640949618915160150e-05 // 0x3f07858e_90a45837
LGAMMA_TC : f64 : 1.46163214496836224576 // 0x3ff762d8_6356be3f
LGAMMA_TF : f64 : -1.21486290535849611461e-01 // 0xbfbf19b9_bcc38a42
LGAMMA_TT : f64 : -3.63867699703950536541e-18 // 0xbc50c7ca_a48a971f
LGAMMA_T0 : f64 : 4.83836122723810047042e-01 // 0x3fdef72b_c8ee38a2
LGAMMA_T1 : f64 : -1.47587722994593911752e-01 // 0xbfc2e427_8dc6c509
LGAMMA_T2 : f64 : 6.46249402391333854778e-02 // 0x3fb08b42_94d5419b
LGAMMA_T3 : f64 : -3.27885410759859649565e-02 // 0xbfa0c9a8_df35b713
LGAMMA_T4 : f64 : 1.79706750811820387126e-02 // 0x3f9266e7_970af9ec
LGAMMA_T5 : f64 : -1.03142241298341437450e-02 // 0xbf851f9f_ba91ec6a
LGAMMA_T6 : f64 : 6.10053870246291332635e-03 // 0x3f78fce0_e370e344
LGAMMA_T7 : f64 : -3.68452016781138256760e-03 // 0xbf6e2eff_b3e914d7
LGAMMA_T8 : f64 : 2.25964780900612472250e-03 // 0x3f6282d3_2e15c915
LGAMMA_T9 : f64 : -1.40346469989232843813e-03 // 0xbf56fe8e_bf2d1af1
LGAMMA_T10 : f64 : 8.81081882437654011382e-04 // 0x3f4cdf0c_ef61a8e9
LGAMMA_T11 : f64 : -5.38595305356740546715e-04 // 0xbf41a610_9c73e0ec
LGAMMA_T12 : f64 : 3.15632070903625950361e-04 // 0x3f34af6d_6c0ebbf7
LGAMMA_T13 : f64 : -3.12754168375120860518e-04 // 0xbf347f24_ecc38c38
LGAMMA_T14 : f64 : 3.35529192635519073543e-04 // 0x3f35fd3e_e8c2d3f4
LGAMMA_U0 : f64 : -7.72156649015328655494e-02 // 0xbfb3c467_e37db0c8
LGAMMA_U1 : f64 : 6.32827064025093366517e-01 // 0x3fe4401e_8b005dff
LGAMMA_U2 : f64 : 1.45492250137234768737 // 0x3ff7475c_d119bd6f
LGAMMA_U3 : f64 : 9.77717527963372745603e-01 // 0x3fef4976_44ea8450
LGAMMA_U4 : f64 : 2.28963728064692451092e-01 // 0x3fcd4eae_f6010924
LGAMMA_U5 : f64 : 1.33810918536787660377e-02 // 0x3f8b678b_bf2bab09
LGAMMA_V1 : f64 : 2.45597793713041134822 // 0x4003a5d7_c2bd619c
LGAMMA_V2 : f64 : 2.12848976379893395361 // 0x40010725_a42b18f5
LGAMMA_V3 : f64 : 7.69285150456672783825e-01 // 0x3fe89dfb_e45050af
LGAMMA_V4 : f64 : 1.04222645593369134254e-01 // 0x3fbaae55_d6537c88
LGAMMA_V5 : f64 : 3.21709242282423911810e-03 // 0x3f6a5abb_57d0cf61
LGAMMA_S0 : f64 : -7.72156649015328655494e-02 // 0xbfb3c467_e37db0c8
LGAMMA_S1 : f64 : 2.14982415960608852501e-01 // 0x3fcb848b_36e20878
LGAMMA_S2 : f64 : 3.25778796408930981787e-01 // 0x3fd4d98f_4f139f59
LGAMMA_S3 : f64 : 1.46350472652464452805e-01 // 0x3fc2bb9c_bee5f2f7
LGAMMA_S4 : f64 : 2.66422703033638609560e-02 // 0x3f9b481c_7e939961
LGAMMA_S5 : f64 : 1.84028451407337715652e-03 // 0x3f5e26b6_7368f239
LGAMMA_S6 : f64 : 3.19475326584100867617e-05 // 0x3f00bfec_dd17e945
LGAMMA_R1 : f64 : 1.39200533467621045958 // 0x3ff645a7_62c4ab74
LGAMMA_R2 : f64 : 7.21935547567138069525e-01 // 0x3fe71a18_93d3dcdc
LGAMMA_R3 : f64 : 1.71933865632803078993e-01 // 0x3fc601ed_ccfbdf27
LGAMMA_R4 : f64 : 1.86459191715652901344e-02 // 0x3f9317ea_742ed475
LGAMMA_R5 : f64 : 7.77942496381893596434e-04 // 0x3f497dda_ca41a95b
LGAMMA_R6 : f64 : 7.32668430744625636189e-06 // 0x3edebaf7_a5b38140
LGAMMA_W0 : f64 : 4.18938533204672725052e-01 // 0x3fdacfe3_90c97d69
LGAMMA_W1 : f64 : 8.33333333333329678849e-02 // 0x3fb55555_5555553b
LGAMMA_W2 : f64 : -2.77777777728775536470e-03 // 0xbf66c16c_16b02e5c
LGAMMA_W3 : f64 : 7.93650558643019558500e-04 // 0x3f4a019f_98cf38b6
LGAMMA_W4 : f64 : -5.95187557450339963135e-04 // 0xbf4380cb_8c0fe741
LGAMMA_W5 : f64 : 8.36339918996282139126e-04 // 0x3f4b67ba_4cdad5d1
LGAMMA_W6 : f64 : -1.63092934096575273989e-03 // 0xbf5ab89d_0b9e43e4

/**
 * sin(π x) for x positive, exactly reduced: x modulo 2, and to within a quarter of 0 by quarters, so π x is never
 * rounded far from where it should be.
 *
 * @param x_in The number, positive and at least 2^-100.
 * @return sin(π x), within 1 ulp; 0 for whole x.
 */
//SPEC: fdlibm e_lgamma_r.c sin_pi, as musl has it
sin_pi_64 :: fn(x_in: f64) -> f64 {
    // x modulo 2
    x := 2.0 * (x_in * 0.5 - intrinsics.floor(x_in * 0.5))
    n := cast[i32](x * 4.0)
    n = (n + 1) / 2
    x -= cast[f64](n) * 0.5
    x *= PI_64
    match n {
        case 1 => return cos_kernel_64(x, 0)
        case 2 => return sin_kernel_64(-x, 0, false)
        case 3 => return -cos_kernel_64(x, 0)
        case _ => return sin_kernel_64(x, 0, false)
    }
}

/**
 * ln |Γ(x)| and Γ(x)'s sign, in f64.
 *
 * @param x_in The number.
 * @return ln |Γ(x)|, within 1 ulp where it's at least 1 in magnitude, and within ulp(1) of it where it's below;
 *     infinity at 0 and the negative whole numbers, where Γ has poles, and for
 *     ±infinity; NaN for NaN. And Γ(x)'s sign, 1 or -1: -1 between -2k - 1 and -2k for whole k ≥ 0, and for -0.
 */
//SPEC: fdlibm e_lgamma_r.c, as musl has it
log_gamma_signed_64 :: fn(x_in: f64) -> (f64, i32) {
    x := x_in
    sign : i32 = 1
    negative :: (bit_cast[u64](x) >> 63) != 0
    ix :: high_word(x) & 0x7fff_ffff
    if ix >= 0x7ff0_0000 {
        return x * x, sign
    }
    // Under 2^-70: -ln |x|
    if ix < (0x3ff - 70) << 20 {
        if negative {
            x = -x
            sign = -1
        }
        return -log_64(x), sign
    }
    nadj := 0.0
    if negative {
        x = -x
        t := sin_pi_64(x)
        if t == 0 {
            // A negative whole number: a pole
            return infinity_64(), sign
        }
        if t > 0 {
            sign = -1
        }
        else {
            t = -t
        }
        nadj = log_64(PI_64 / (t * x))
    }
    r := 0.0
    if (ix == 0x3ff0_0000 || ix == 0x4000_0000) && low_word(x) == 0 {
        // 1 and 2
        r = 0
    }
    else if ix < 0x4000_0000 {
        // Below 2
        y := 0.0
        i : i32 = 0
        if ix <= 0x3fec_cccc {
            // ln Γ(x) = ln Γ(x + 1) - ln x
            r = -log_64(x)
            if ix >= 0x3fe7_6944 {
                y = 1.0 - x
                i = 0
            }
            else if ix >= 0x3fcd_a661 {
                y = x - (LGAMMA_TC - 1.0)
                i = 1
            }
            else {
                y = x
                i = 2
            }
        }
        else {
            r = 0
            if ix >= 0x3ffb_b4c3 {
                // From 1.7316
                y = 2.0 - x
                i = 0
            }
            else if ix >= 0x3ff3_b4c4 {
                // From 1.23
                y = x - LGAMMA_TC
                i = 1
            }
            else {
                y = x - 1.0
                i = 2
            }
        }
        if i == 0 {
            z :: y * y
            p1 :: LGAMMA_A0 + z * (LGAMMA_A2 + z * (LGAMMA_A4 + z * (LGAMMA_A6 + z * (LGAMMA_A8 + z * LGAMMA_A10))))
            p2 :: z * (LGAMMA_A1 + z * (LGAMMA_A3 + z * (LGAMMA_A5 + z * (LGAMMA_A7 + z * (LGAMMA_A9
                + z * LGAMMA_A11)))))
            p :: y * p1 + p2
            r += p - 0.5 * y
        }
        else if i == 1 {
            z :: y * y
            w :: z * y
            p1 :: LGAMMA_T0 + w * (LGAMMA_T3 + w * (LGAMMA_T6 + w * (LGAMMA_T9 + w * LGAMMA_T12)))
            p2 :: LGAMMA_T1 + w * (LGAMMA_T4 + w * (LGAMMA_T7 + w * (LGAMMA_T10 + w * LGAMMA_T13)))
            p3 :: LGAMMA_T2 + w * (LGAMMA_T5 + w * (LGAMMA_T8 + w * (LGAMMA_T11 + w * LGAMMA_T14)))
            p :: z * p1 - (LGAMMA_TT - w * (p2 + y * p3))
            r += LGAMMA_TF + p
        }
        else {
            p1 :: y * (LGAMMA_U0 + y * (LGAMMA_U1 + y * (LGAMMA_U2 + y * (LGAMMA_U3 + y * (LGAMMA_U4
                + y * LGAMMA_U5)))))
            p2 :: 1.0 + y * (LGAMMA_V1 + y * (LGAMMA_V2 + y * (LGAMMA_V3 + y * (LGAMMA_V4 + y * LGAMMA_V5))))
            r += -0.5 * y + p1 / p2
        }
    }
    else if ix < 0x4020_0000 {
        // From 2 to 8: ln Γ(2 + y) and ln of the product up to x
        i :: cast[i32](x)
        y :: x - cast[f64](i)
        p :: y * (LGAMMA_S0 + y * (LGAMMA_S1 + y * (LGAMMA_S2 + y * (LGAMMA_S3 + y * (LGAMMA_S4 + y * (LGAMMA_S5 + y
            * LGAMMA_S6))))))
        q :: 1.0 + y * (LGAMMA_R1 + y * (LGAMMA_R2 + y * (LGAMMA_R3 + y * (LGAMMA_R4 + y * (LGAMMA_R5
            + y * LGAMMA_R6)))))
        r = 0.5 * y + p / q
        z := 1.0
        k := i
        loop {
            z *= y + cast[f64](k - 1)
            k -= 1
        }
        while k >= 3
        if i >= 3 {
            r += log_64(z)
        }
    }
    else if ix < 0x4390_0000 {
        // From 8 to 2^58: Stirling's series
        t :: log_64(x)
        z :: 1.0 / x
        y :: z * z
        w :: LGAMMA_W0 + z * (LGAMMA_W1 + y * (LGAMMA_W2 + y * (LGAMMA_W3 + y * (LGAMMA_W4 + y * (LGAMMA_W5 + y
            * LGAMMA_W6)))))
        r = (x - 0.5) * (t - 1.0) + w
    }
    else {
        r = x * (log_64(x) - 1.0)
    }
    if negative {
        r = nadj - r
    }
    return r, sign
}

/**
 * ln |Γ(x)| in f64.
 *
 * @param x The number.
 * @return As log_gamma_signed_64 gives it, without the sign.
 */
log_gamma_64 :: fn(x: f64) -> f64 {
    r, _ :: log_gamma_signed_64(x)
    return r
}

/* Γ's Lanczos approximation, g = GAMMA_G_MINUS_HALF + 0.5, as a rational function S(x) = Snum(x) / Sden(x) */
GAMMA_G_MINUS_HALF : f64 : 5.524680040776729583740234375
GAMMA_NUMERATOR :: f64.[
    23531376880.410759688572007674451636754734846804940, 42919803642.649098768957899047001988850926355848959,
    35711959237.355668049440185451547166705960488635843, 17921034426.037209699919755754458931112671403265390,
    6039542586.3520280050642916443072979210699388420708, 1439720407.3117216736632230727949123939715485786772,
    248874557.86205415651146038641322942321632125127801, 31426415.585400194380614231628318205362874684987640,
    2876370.6289353724412254090516208496135991145378768, 186056.26539522349504029498971604569928220784236328,
    8071.6720023658162106380029022722506138218516325024, 210.82427775157934587250973392071336271166969580291,
    2.5066282746310002701649081771338373386264310793408,
]
GAMMA_DENOMINATOR :: f64.[0, 39916800, 120543840, 150917976, 105258076, 45995730, 13339535, 2637558, 357423, 32670,
    1925, 66, 1]
/** 0! to 22!, exact in f64, which Γ of a whole number up to 23 is. */
FACTORIALS :: f64.[1, 1, 2, 6, 24, 120, 720, 5040, 40320, 362880, 3628800, 39916800, 479001600, 6227020800,
    87178291200, 1307674368000, 20922789888000, 355687428096000, 6402373705728000, 121645100408832000.0,
    2432902008176640000.0, 51090942171709440000.0, 1124000727777607680000.0]

/**
 * Γ's Lanczos sum, S(x).
 *
 * @param x The number, positive.
 * @return S(x), Horner in x below 8 and in 1/x from 8, so it doesn't overflow.
 */
//SPEC: musl src/math/tgamma.c S
gamma_sum_64 :: fn(x: f64) -> f64 {
    numerator := 0.0
    denominator := 0.0
    if x < 8 {
        i := GAMMA_NUMERATOR.count
        loop {
            i -= 1
            numerator = numerator * x + GAMMA_NUMERATOR[i]
            denominator = denominator * x + GAMMA_DENOMINATOR[i]
        }
        while i > 0
    }
    else {
        for i in 0..<GAMMA_NUMERATOR.count {
            numerator = numerator / x + GAMMA_NUMERATOR[i]
            denominator = denominator / x + GAMMA_DENOMINATOR[i]
        }
    }
    return numerator / denominator
}

/**
 * The gamma function, Γ(x), in f64.
 *
 * @param x The number.
 * @return Γ(x), within 6 ulp, and exact for whole numbers up to 23; NaN at the negative whole
 *     numbers and -infinity, ±infinity at ±0 and where it overflows, ±0 where it underflows, NaN for NaN.
 */
//SPEC: musl src/math/tgamma.c
gamma_64 :: fn(x: f64) -> f64 {
    ix :: high_word(x) & 0x7fff_ffff
    negative :: (bit_cast[u64](x) >> 63) != 0
    if ix >= 0x7ff0_0000 {
        return x + infinity_64()
    }
    // Under 2^-54: 1/x
    if ix < (0x3ff - 54) << 20 {
        return 1 / x
    }
    if x == intrinsics.floor(x) {
        if negative {
            return nan_64()
        }
        if x <= cast[f64](FACTORIALS.count) {
            index :: cast[usize](x) - 1
            if index < FACTORIALS.count {
                return FACTORIALS[index]
            }
        }
    }
    // From 184, Γ overflows; down to -184, it underflows
    if ix >= 0x4067_0000 {
        if negative {
            if intrinsics.floor(x) * 0.5 == intrinsics.floor(x * 0.5) {
                return 0
            }
            return -0.0
        }
        return infinity_64()
    }
    magnitude :: abs(x)
    // y = |x| + g - 0.5, and dy what that lost
    y := magnitude + GAMMA_G_MINUS_HALF
    dy := 0.0
    if magnitude > GAMMA_G_MINUS_HALF {
        dy = y - magnitude
        dy -= GAMMA_G_MINUS_HALF
    }
    else {
        dy = y - GAMMA_G_MINUS_HALF
        dy -= magnitude
    }
    z := magnitude - 0.5
    r := gamma_sum_64(magnitude) * exp_64(-y)
    if negative {
        // Reflection: Γ(-x) = -π / (x Γ(x) sin(π x))
        r = -PI_64 / (sin_pi_64(magnitude) * magnitude * r)
        dy = -dy
        z = -z
    }
    r += dy * (GAMMA_G_MINUS_HALF + 0.5) * r / y
    z = power_64(y, 0.5 * z)
    return r * z * z
}
