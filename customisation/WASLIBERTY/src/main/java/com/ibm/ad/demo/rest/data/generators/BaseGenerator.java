package com.ibm.ad.demo.rest.data.generators;

import java.time.ZonedDateTime;
import java.util.List;
import java.util.Random;

public class BaseGenerator {
    private final static Random RNG = new Random();

    public static <T> T randomItem(List<T> list) {
        return list.get(RNG.nextInt(list.size()));
    }

    /** precision 100.0 is good for price, 10.0 */
    public static double randomDouble(double min, double max, double precision) {
        double randomValue = min + (max - min) * RNG.nextDouble();
        return Math.round(randomValue * precision) / precision;
    }

    public static boolean shouldDo(double ratio) {
        return RNG.nextDouble() < ratio;
    }

    public static int randomInt(int min, int max) {
        return RNG.nextInt(min, max + 1);
    }

    public static ZonedDateTime nowWithRandomOffset(int maxOffset) {
        final ZonedDateTime now = ZonedDateTime.now();
        if (maxOffset == 0) {
            return now;
        } else {
            return now.minusSeconds(randomInt(0, maxOffset));
        }
    }
}
