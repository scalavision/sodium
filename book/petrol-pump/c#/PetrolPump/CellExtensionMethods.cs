﻿using System.Collections.Generic;
using Sodium;

namespace PetrolPump
{
    public static class CellExtensionMethods
    {
        public static Stream<T> Changes<T>(this DiscreteCell<T> cell)
        {
            return cell.Values.Snapshot(cell, (n, o) => EqualityComparer<T>.Default.Equals(o, n) ? Maybe.Nothing<T>() : Maybe.Just(n)).FilterMaybe();
        }
    }
}