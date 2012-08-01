//
// Copyright (C) 2009 The University of Melbourne.
// This file may only be copied under the terms of the GNU Library General
// Public License - see the file COPYING.LIB in the Mercury distribution.
//
// This is the superclass of all classes generated by the Java back-end
// which correspond to Mercury-defined enumeration types.
//

package jmercury.runtime;

public abstract class MercuryEnum {
    public final int MR_value;

    protected MercuryEnum(int val) {
        MR_value = val;
    }

    @Override 
    public boolean equals(Object o) {
        return o != null && o instanceof MercuryEnum &&
            ((MercuryEnum)o).MR_value == this.MR_value;
    }

    @Override
    public int hashCode() {
        return MR_value;
    }
}